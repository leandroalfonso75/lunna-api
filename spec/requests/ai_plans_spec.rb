require "rails_helper"

RSpec.describe "/api/items/:id/ai-plan", type: :request do
  before { ApplicationController.cache_store.clear }

  let(:company) { create(:company, :with_ai) }
  let(:user) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }
  let(:query) { { account_id: account.id } }

  let!(:metric) do
    create(:item_metric, ml_account: account, item_id: "MLB1", title: "Item A", status: "active", sku: "SKU-A",
      price: 100.0, stock: 10, visits_30d: 100, prev_visits_30d: 90, units_30d: 10, prev_units_30d: 8,
      revenue_30d: 1000.0, prev_revenue_30d: 800.0, fees_30d: 100.0, conversion_30d: 10.0)
  end

  before { create(:ml_item, ml_account: account, item_id: "MLB1", price: 100.0) }

  describe "POST (gerar)" do
    it "cria o plano como pending, enfileira o job e responde 202" do
      expect { post "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user) }
        .to have_enqueued_job(Ai::ActionPlanJob)

      expect(response).to have_http_status(:accepted)
      expect(json["ai_plan"]).to include("status" => "pending", "text" => "", "error" => nil)
      expect(AiPlan.find_by(ml_account: account, item_id: "MLB1")).to be_present
    end

    it "gerar de novo depois de pronto zera o texto e enfileira outro job" do
      create(:ai_plan, ml_account: account, item_id: "MLB1", status: "done", text: "plano antigo")

      expect { post "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user) }
        .to have_enqueued_job(Ai::ActionPlanJob)

      expect(json["ai_plan"]).to include("status" => "pending", "text" => "")
    end

    it "já em geração (recente) -> 409 e nenhum job novo" do
      create(:ai_plan, ml_account: account, item_id: "MLB1", status: "running")

      expect { post "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user) }
        .not_to have_enqueued_job(Ai::ActionPlanJob)

      expect(response).to have_http_status(:conflict)
    end

    it "geração parada há mais de 5 min (worker caiu) pode ser recomeçada" do
      create(:ai_plan, ml_account: account, item_id: "MLB1", status: "running", updated_at: 6.minutes.ago)

      post "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user)

      expect(response).to have_http_status(:accepted)
    end

    it "empresa sem chave/modelo -> 422 com a mensagem de configuração, sem plano nem job" do
      sem_ia_user = create(:user, company: create(:company))
      sem_ia_account = create(:ml_account, company: sem_ia_user.company)
      create(:item_metric, ml_account: sem_ia_account, item_id: "MLB2", title: "Item B", status: "active")

      expect { post "/api/items/MLB2/ai-plan", params: { account_id: sem_ia_account.id }, headers: auth_headers(sem_ia_user) }
        .not_to have_enqueued_job(Ai::ActionPlanJob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to eq([ "Configure a chave e o modelo da OpenRouter em Configurações › Empresa." ])
      expect(AiPlan.count).to eq(0)
    end

    it "anúncio de outra empresa -> 404" do
      post "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(create(:user))

      expect(response).to have_http_status(:not_found)
    end

    it "limita 10 chamadas por minuto por empresa (429)" do
      11.times { post "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user) }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "GET (polling)" do
    it "sem plano -> ai_plan nulo" do
      get "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("ai_plan" => nil)
    end

    it "devolve status, texto parcial e erro" do
      create(:ai_plan, ml_account: account, item_id: "MLB1", status: "running", text: "Diagnóstico: ")

      get "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user)

      expect(json["ai_plan"]).to include("status" => "running", "text" => "Diagnóstico: ", "error" => nil)
    end

    it "gerando há mais de 5 min sem gravação vira erro (não fica esperando pra sempre)" do
      create(:ai_plan, ml_account: account, item_id: "MLB1", status: "running", updated_at: 6.minutes.ago)

      get "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user)

      expect(json["ai_plan"]).to include("status" => "error", "error" => "A geração foi interrompida. Tente de novo.")
    end

    it "anúncio de outra empresa -> 404" do
      get "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(create(:user))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE (parar)" do
    it "marca como cancelled o plano em geração" do
      plan = create(:ai_plan, ml_account: account, item_id: "MLB1", status: "running")

      delete "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user)

      expect(response).to have_http_status(:no_content)
      expect(plan.reload.status).to eq("cancelled")
    end

    it "sem plano em geração não faz nada (204)" do
      plan = create(:ai_plan, ml_account: account, item_id: "MLB1", status: "done", text: "pronto")

      delete "/api/items/MLB1/ai-plan", params: query, headers: auth_headers(user)

      expect(response).to have_http_status(:no_content)
      expect(plan.reload.status).to eq("done")
    end
  end
end
