require "rails_helper"

RSpec.describe "POST /api/items/:id/ai-plan", type: :request do
  before { ApplicationController.cache_store.clear }

  let(:company) { create(:company, :with_ai) }
  let(:user) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }
  let(:url) { "https://openrouter.ai/api/v1/chat/completions" }

  let!(:metric) do
    create(:item_metric, ml_account: account, item_id: "MLB1", title: "Item A", status: "active", sku: "SKU-A",
      price: 100.0, stock: 10, visits_30d: 100, prev_visits_30d: 90, units_30d: 10, prev_units_30d: 8,
      revenue_30d: 1000.0, prev_revenue_30d: 800.0, fees_30d: 100.0, conversion_30d: 10.0)
  end

  before { create(:ml_item, ml_account: account, item_id: "MLB1", price: 100.0) }

  def sse_body
    <<~SSE
      data: {"choices":[{"index":0,"delta":{"content":"Diagnóstico: "}}]}

      data: {"choices":[{"index":0,"delta":{"content":"tudo certo."}}]}

      data: [DONE]

    SSE
  end

  it "responde em streaming (data: ...) e termina com event: done" do
    stub_request(:post, url).to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: sse_body)

    post "/api/items/MLB1/ai-plan", params: { account_id: account.id }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data: "Diagnóstico: "')
    expect(response.body).to include("event: done")
  end

  it "anúncio de outra empresa -> 404 antes de abrir o stream" do
    other_user = create(:user)

    post "/api/items/MLB1/ai-plan", params: { account_id: account.id }, headers: auth_headers(other_user)

    expect(response).to have_http_status(:not_found)
  end

  it "empresa sem chave/modelo configurados -> event: error com a mensagem de configuração" do
    sem_ia_user = create(:user, company: create(:company))
    sem_ia_account = create(:ml_account, company: sem_ia_user.company)
    create(:ml_item, ml_account: sem_ia_account, item_id: "MLB2", price: 100.0)
    create(:item_metric, ml_account: sem_ia_account, item_id: "MLB2", title: "Item A", status: "active", sku: "SKU-A",
      price: 100.0, stock: 10, visits_30d: 100, prev_visits_30d: 90, units_30d: 10, prev_units_30d: 8,
      revenue_30d: 1000.0, prev_revenue_30d: 800.0, fees_30d: 100.0, conversion_30d: 10.0)

    post "/api/items/MLB2/ai-plan", params: { account_id: sem_ia_account.id }, headers: auth_headers(sem_ia_user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("event: error")
    expect(response.body).to include("Configure a chave e o modelo da OpenRouter em Configurações › Empresa.")
    expect(WebMock).not_to have_requested(:post, url)
  end

  it "limita 10 chamadas por minuto por empresa (429)" do
    stub_request(:post, url).to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: sse_body)

    10.times { post "/api/items/MLB1/ai-plan", params: { account_id: account.id }, headers: auth_headers(user) }
    post "/api/items/MLB1/ai-plan", params: { account_id: account.id }, headers: auth_headers(user)

    expect(response).to have_http_status(:too_many_requests)
  end
end
