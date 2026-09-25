require "rails_helper"

RSpec.describe "/api/ml_accounts", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }

  before do
    stub_env(
      "ML_CLIENT_ID" => "client-123",
      "ML_CLIENT_SECRET" => "secret-abc",
      "API_URL" => "https://api.lunna.test"
    )
  end

  describe "GET /api/ml_accounts" do
    it "lista as contas da própria empresa sem expor os tokens" do
      create(:ml_account, company: company, nickname: "LOJA A")
      create(:ml_account) # outra empresa

      get "/api/ml_accounts", headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      expect(json["ml_accounts"].size).to eq(1)
      expect(json["ml_accounts"].first["nickname"]).to eq("LOJA A")
      expect(json["ml_accounts"].first.keys).not_to include("access_token", "refresh_token")
    end
  end

  describe "POST /api/ml_accounts/authorize" do
    it "member não pode (403)" do
      post "/api/ml_accounts/authorize", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end

    it "sem ML_CLIENT_ID/SECRET devolve 422" do
      stub_env("ML_CLIENT_ID" => nil, "ML_CLIENT_SECRET" => nil)

      post "/api/ml_accounts/authorize", headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to eq([ "Integração com o Mercado Livre não configurada." ])
    end

    it "admin recebe a URL de autorização e o state é gravado com company/user" do
      post "/api/ml_accounts/authorize", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)

      uri = URI.parse(json["url"])
      query = URI.decode_www_form(uri.query).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("https://auth.mercadolivre.com.br/authorization")
      expect(query["client_id"]).to eq([ "client-123" ])
      expect(query["redirect_uri"]).to eq([ "https://api.lunna.test/auth/ml/callback" ])
      expect(query["state"].first).to be_present

      state = MlOauthState.find(query["state"].first)
      expect(state.company_id).to eq(company.id)
      expect(state.user_id).to eq(admin.id)
    end

    it "apaga states com mais de 1h antes de criar o novo" do
      create(:ml_oauth_state, company: company, user: admin, created_at: 2.hours.ago)

      post "/api/ml_accounts/authorize", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(MlOauthState.count).to eq(1)
    end
  end

  describe "POST /api/ml_accounts/connect" do
    let(:state) { create(:ml_oauth_state, company: company, user: admin) }

    def stub_token_exchange(fixture: "oauth_token")
      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .to_return(status: 200, body: ml_fixture(fixture))
    end

    def stub_users_me
      stub_request(:get, "https://api.mercadolibre.com/users/me")
        .to_return(status: 200, body: ml_fixture("users_me"))
    end

    it "member não pode (403)" do
      post "/api/ml_accounts/connect", params: { code: "abc", state: state.state }, headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end

    it "state inexistente → 422 code: expirada" do
      post "/api/ml_accounts/connect", params: { code: "abc", state: "nao-existe" }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("expirada")
      expect(json["errors"]).to eq([ "Autorização expirada. Tente conectar de novo." ])
    end

    it "state com mais de 1h → 422 code: expirada" do
      state.update_columns(created_at: 1.hour.ago - 1.second)

      post "/api/ml_accounts/connect", params: { code: "abc", state: state.state }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("expirada")
    end

    it "state gerado por outro usuário da MESMA empresa → 403 code: sem_permissao, state intacto" do
      other_admin = create(:user, :admin, company: company)
      state_from_other = create(:ml_oauth_state, company: company, user: other_admin)

      post "/api/ml_accounts/connect", params: { code: "abc", state: state_from_other.state }, headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("sem_permissao")
      expect(MlOauthState.exists?(state_from_other.state)).to be true
    end

    it "state de outra empresa → 403 code: sem_permissao, state intacto" do
      other_company = create(:company)
      other_admin = create(:user, :admin, company: other_company)
      state_from_other_company = create(:ml_oauth_state, company: other_company, user: other_admin)

      post "/api/ml_accounts/connect",
        params: { code: "abc", state: state_from_other_company.state },
        headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("sem_permissao")
      expect(MlOauthState.exists?(state_from_other_company.state)).to be true
    end

    it "app sem client id/secret → 422 code: erro_config" do
      target_state = state
      stub_env("ML_CLIENT_ID" => nil, "ML_CLIENT_SECRET" => nil)

      post "/api/ml_accounts/connect", params: { code: "abc", state: target_state.state }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("erro_config")
    end

    it "troca do code falhou → 422 code: erro" do
      target_state = state
      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .to_return(status: 400, body: ml_fixture("error_invalid_grant"))

      post "/api/ml_accounts/connect", params: { code: "abc", state: target_state.state }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("erro")
      expect(MlAccount.count).to eq(0)
    end

    it "resposta sem refresh_token → 422 code: sem_offline_access, não grava" do
      target_state = state
      stub_token_exchange(fixture: "oauth_token_no_refresh")

      post "/api/ml_accounts/connect", params: { code: "abc", state: target_state.state }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("sem_offline_access")
      expect(MlAccount.count).to eq(0)
    end

    it "seller já vinculado a outra empresa → 409 code: outra_empresa, não grava" do
      target_state = state
      other_company = create(:company)
      existing = create(:ml_account, company: other_company, seller_id: 430_014_725, access_token: "tok-antigo")
      stub_token_exchange
      stub_users_me

      post "/api/ml_accounts/connect", params: { code: "abc", state: target_state.state }, headers: auth_headers(admin)

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("outra_empresa")
      expect(existing.reload.company_id).to eq(other_company.id)
      expect(existing.access_token).to eq("tok-antigo")
    end

    it "sucesso: cria a conta, enfileira Ml::SyncJob e consome o state" do
      target_state = state
      stub_token_exchange
      stub_users_me

      expect {
        post "/api/ml_accounts/connect", params: { code: "abc", state: target_state.state }, headers: auth_headers(admin)
      }.to have_enqueued_job(Ml::SyncJob)

      expect(response).to have_http_status(:ok)
      expect(json["code"]).to eq("conectada")
      expect(json["ml_account"]["nickname"]).to eq("LUNNA_SHOP")
      expect(json["ml_account"]).not_to have_key("access_token")

      account = MlAccount.find_by(seller_id: 430_014_725)
      expect(account.company_id).to eq(company.id)
      expect(account.access_token).to eq("APP_USR-access-1")
      expect(account.refresh_token).to eq("TG-refresh-1")
      expect(account.status).to eq("active")
      expect(account.connected_by_user_id).to eq(admin.id)
      expect(MlOauthState.exists?(target_state.state)).to be false
    end

    it "reconexão na mesma empresa atualiza os tokens sem duplicar a conta" do
      target_state = state
      existing = create(:ml_account, company: company, seller_id: 430_014_725, access_token: "tok-antigo")
      stub_token_exchange
      stub_users_me

      post "/api/ml_accounts/connect", params: { code: "abc", state: target_state.state }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json["code"]).to eq("conectada")
      expect(MlAccount.where(seller_id: 430_014_725).count).to eq(1)
      expect(existing.reload.access_token).to eq("APP_USR-access-1")
    end
  end

  describe "DELETE /api/ml_accounts/:id" do
    it "member não pode (403)" do
      account = create(:ml_account, company: company)

      delete "/api/ml_accounts/#{account.id}", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end

    it "conta de outra empresa devolve 404" do
      other_account = create(:ml_account)

      delete "/api/ml_accounts/#{other_account.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end

    it "admin desconecta a conta da própria empresa (204)" do
      account = create(:ml_account, company: company)

      delete "/api/ml_accounts/#{account.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:no_content)
      expect(MlAccount.exists?(account.id)).to be false
    end
  end
end
