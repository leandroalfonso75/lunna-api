require "rails_helper"

RSpec.describe "/api/company", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }

  describe "GET /api/company" do
    it "qualquer logado vê a empresa" do
      get "/api/company", headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      expect(json["company"]["id"]).to eq(company.id)
    end

    it "devolve 401 sem token" do
      get "/api/company"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/company" do
    it "admin atualiza os parâmetros de negócio" do
      patch "/api/company", params: { name: "Nova Razão Social", tax_pct: 12.5 }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json["company"]["name"]).to eq("Nova Razão Social")
      expect(json["company"]["tax_pct"]).to eq(12.5)
    end

    it "member não pode (403)" do
      patch "/api/company", params: { name: "Tentativa" }, headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
      expect(json["errors"]).to eq([ "sem permissão" ])
      expect(company.reload.name).not_to eq("Tentativa")
    end

    it "devolve 422 pra parâmetro inválido" do
      patch "/api/company", params: { tax_pct: 200 }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to be_present
    end

    it "recalcula item_metrics de todas as contas da empresa" do
      account_a = create(:ml_account, company: company)
      account_b = create(:ml_account, company: company)

      expect(Painel::ItemMetrics).to receive(:refresh).with(account_a)
      expect(Painel::ItemMetrics).to receive(:refresh).with(account_b)

      patch "/api/company", params: { tax_pct: 12 }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
    end

    it "mudar só ai_model não recalcula item_metrics" do
      create(:ml_account, company: company)

      expect(Painel::ItemMetrics).not_to receive(:refresh)

      patch "/api/company", params: { ai_model: "anthropic/claude-sonnet-4.5" }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
    end

    describe "OpenRouter (DECISOES §10)" do
      it "salva a chave e o modelo" do
        patch "/api/company",
          params: { ai_model: "anthropic/claude-sonnet-4.5", openrouter_api_key: "sk-or-v1-nova-chave" },
          headers: auth_headers(admin)

        expect(response).to have_http_status(:ok)
        expect(json["company"]["ai_model"]).to eq("anthropic/claude-sonnet-4.5")
        expect(json["company"]["ai_configured"]).to eq(true)
        expect(json["company"]["ai_key_hint"]).to eq("…have")
        expect(company.reload.openrouter_api_key).to eq("sk-or-v1-nova-chave")
      end

      it "a resposta nunca contém a chave" do
        patch "/api/company",
          params: { ai_model: "anthropic/claude-sonnet-4.5", openrouter_api_key: "sk-or-v1-segredo-super-secreto" },
          headers: auth_headers(admin)

        expect(response.body).not_to include("sk-or-v1-segredo-super-secreto")
      end

      it "openrouter_api_key ausente ou vazio mantém a chave atual" do
        company.update!(openrouter_api_key: "sk-or-v1-antiga", ai_model: "anthropic/claude-sonnet-4.5")

        patch "/api/company", params: { openrouter_api_key: "" }, headers: auth_headers(admin)

        expect(response).to have_http_status(:ok)
        expect(company.reload.openrouter_api_key).to eq("sk-or-v1-antiga")
      end

      it "remove_openrouter_api_key: true apaga a chave" do
        company.update!(openrouter_api_key: "sk-or-v1-antiga", ai_model: "anthropic/claude-sonnet-4.5")

        patch "/api/company", params: { remove_openrouter_api_key: true }, headers: auth_headers(admin)

        expect(response).to have_http_status(:ok)
        expect(json["company"]["ai_configured"]).to eq(false)
        expect(json["company"]["ai_key_hint"]).to be_nil
        expect(company.reload.openrouter_api_key).to be_nil
      end
    end
  end
end
