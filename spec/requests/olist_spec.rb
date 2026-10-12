require "rails_helper"

RSpec.describe "Olist ERP", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }
  let(:token_url) { "https://accounts.tiny.com.br/realms/tiny/protocol/openid-connect/token" }

  before do
    stub_env(
      "OLIST_CLIENT_ID" => "client-olist", "OLIST_CLIENT_SECRET" => "secret-olist",
      "API_URL" => "https://api.lunna.test", "FRONT_URL" => "https://front.lunna.test"
    )
  end

  describe "GET /api/olist" do
    it "mostra que não está conectado" do
      get "/api/olist", headers: auth_headers(member)

      expect(json["olist"]).to eq("configured" => true, "connected" => false)
    end

    it "mostra a conexão da própria empresa, sem expor tokens" do
      create(:olist_connection, company: company, connected_by_user: admin)

      get "/api/olist", headers: auth_headers(member)

      expect(json["olist"]).to include("connected" => true, "status" => "active", "connected_by" => admin.name)
      expect(response.body).not_to include("olist-access-token", "olist-refresh-token")
    end
  end

  describe "POST /api/olist/authorize" do
    it "admin recebe a URL de autorização e o state fica gravado" do
      post "/api/olist/authorize", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      state = OlistOauthState.last
      expect(state).to have_attributes(company_id: company.id, user_id: admin.id)
      expect(json["url"]).to include("accounts.tiny.com.br", "state=#{state.state}")
    end

    it "member não pode (403)" do
      post "/api/olist/authorize", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end

    it "422 sem as chaves no ambiente" do
      stub_env("OLIST_CLIENT_ID" => nil)

      post "/api/olist/authorize", headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /auth/olist/callback" do
    let(:state) { OlistOauthState.create!(state: SecureRandom.uuid, company: company, user: admin) }

    def stub_token(status: 200, body: { access_token: "A", refresh_token: "R", expires_in: 14_400, refresh_expires_in: 86_400 })
      stub_request(:post, token_url).to_return(status: status, body: body.to_json)
    end

    it "conclui a conexão, consome o state e redireciona" do
      stub_token

      get "/auth/olist/callback", params: { code: "abc", state: state.state }

      expect(response).to redirect_to("https://front.lunna.test/configuracoes?olist=conectado")
      connection = company.reload.olist_connection
      expect(connection).to have_attributes(access_token: "A", refresh_token: "R", status: "active", connected_by_user_id: admin.id)
      expect(OlistOauthState.exists?(state.state)).to be false
    end

    it "reconectar atualiza a conexão existente" do
      create(:olist_connection, company: company, status: "reauth_required")
      stub_token

      get "/auth/olist/callback", params: { code: "abc", state: state.state }

      expect(OlistConnection.where(company: company).count).to eq(1)
      expect(company.reload.olist_connection.status).to eq("active")
    end

    it "state desconhecido não grava nada" do
      get "/auth/olist/callback", params: { code: "abc", state: "inventado" }

      expect(response).to redirect_to("https://front.lunna.test/configuracoes?olist=expirada")
      expect(OlistConnection.count).to eq(0)
    end

    it "state expirado não é aceito" do
      old = OlistOauthState.create!(state: SecureRandom.uuid, company: company, user: admin, created_at: 2.hours.ago)

      get "/auth/olist/callback", params: { code: "abc", state: old.state }

      expect(response).to redirect_to("https://front.lunna.test/configuracoes?olist=expirada")
      expect(OlistConnection.count).to eq(0)
    end

    it "state é de uso único" do
      stub_token
      get "/auth/olist/callback", params: { code: "abc", state: state.state }

      get "/auth/olist/callback", params: { code: "abc", state: state.state }

      expect(response).to redirect_to("https://front.lunna.test/configuracoes?olist=expirada")
    end

    it "usuário que cancelou" do
      get "/auth/olist/callback", params: { error: "access_denied" }

      expect(response).to redirect_to("https://front.lunna.test/configuracoes?olist=cancelada")
    end

    it "falha na troca do code não grava conexão" do
      stub_token(status: 400, body: {})

      get "/auth/olist/callback", params: { code: "ruim", state: state.state }

      expect(response).to redirect_to("https://front.lunna.test/configuracoes?olist=erro")
      expect(OlistConnection.count).to eq(0)
    end
  end

  describe "DELETE /api/olist" do
    it "admin desconecta" do
      create(:olist_connection, company: company)

      delete "/api/olist", headers: auth_headers(admin)

      expect(response).to have_http_status(:no_content)
      expect(OlistConnection.count).to eq(0)
    end

    it "member não pode (403)" do
      delete "/api/olist", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/olist/sync" do
    include ActiveJob::TestHelper

    before { ActiveJob::Base.queue_adapter = :test }

    it "qualquer usuário pede a atualização: cria a rodada manual e enfileira o job" do
      create(:olist_connection, company: company)

      expect { post "/api/olist/sync", headers: auth_headers(member) }.to have_enqueued_job(Olist::SyncJob)

      expect(response).to have_http_status(:accepted)
      run = company.olist_sync_runs.last
      expect(run).to have_attributes(trigger: "manual", status: "running", requested_by_user_id: member.id)
      expect(json["sync_run"]["id"]).to eq(run.id)
    end

    it "se já há uma em andamento, devolve essa em vez de abrir outra" do
      create(:olist_connection, company: company)
      running = create(:olist_sync_run, company: company, started_at: 1.minute.ago)

      expect { post "/api/olist/sync", headers: auth_headers(member) }.not_to have_enqueued_job(Olist::SyncJob)

      expect(response).to have_http_status(:ok)
      expect(json).to include("already_running" => true)
      expect(json["sync_run"]["id"]).to eq(running.id)
      expect(OlistSyncRun.count).to eq(1)
    end

    it "422 sem conexão" do
      post "/api/olist/sync", headers: auth_headers(member)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/olist/sync_runs" do
    it "lista só as rodadas da empresa, da mais nova para a mais antiga" do
      older = create(:olist_sync_run, company: company, started_at: 2.hours.ago, status: "success")
      newer = create(:olist_sync_run, company: company, started_at: 1.hour.ago, status: "failed")
      other = create(:olist_sync_run)

      get "/api/olist/sync_runs", headers: auth_headers(member)

      ids = json["sync_runs"].map { |r| r["id"] }
      expect(ids).to eq([ newer.id, older.id ])
      expect(ids).not_to include(other.id)
    end
  end
end
