require "rails_helper"

RSpec.describe "POST /api/items/:id/ai-plan", type: :request do
  # `rate_limit` usa o cache store do controller; `Ai::ActionPlan` memoiza o
  # cliente globalmente — os dois precisam ser resetados entre exemplos.
  before do
    ApplicationController.cache_store.clear
    Ai::ActionPlan.instance_variable_set(:@client, nil)
  end

  after { Ai::ActionPlan.instance_variable_set(:@client, nil) }

  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  let!(:metric) do
    create(:item_metric, ml_account: account, item_id: "MLB1", title: "Item A", status: "active", sku: "SKU-A",
      price: 100.0, stock: 10, visits_30d: 100, prev_visits_30d: 90, units_30d: 10, prev_units_30d: 8,
      revenue_30d: 1000.0, prev_revenue_30d: 800.0, fees_30d: 100.0, conversion_30d: 10.0)
  end

  before { create(:ml_item, ml_account: account, item_id: "MLB1", price: 100.0) }

  def sse_body
    <<~SSE
      event: message_start
      data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-5","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}

      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Diagnóstico: "}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"tudo certo."}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":5}}

      event: message_stop
      data: {"type":"message_stop"}

    SSE
  end

  it "responde em streaming (data: ...) e termina com event: done" do
    stub_env("ANTHROPIC_API_KEY" => "fake-key")
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: sse_body)

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

  it "sem ANTHROPIC_API_KEY -> event: error" do
    stub_env("ANTHROPIC_API_KEY" => nil)

    post "/api/items/MLB1/ai-plan", params: { account_id: account.id }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("event: error")
    expect(response.body).to include("Integração com a IA não configurada.")
  end

  it "limita 10 chamadas por minuto por empresa (429)" do
    stub_env("ANTHROPIC_API_KEY" => "fake-key")
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: sse_body)

    10.times { post "/api/items/MLB1/ai-plan", params: { account_id: account.id }, headers: auth_headers(user) }
    post "/api/items/MLB1/ai-plan", params: { account_id: account.id }, headers: auth_headers(user)

    expect(response).to have_http_status(:too_many_requests)
  end
end
