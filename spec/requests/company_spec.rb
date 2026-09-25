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
  end
end
