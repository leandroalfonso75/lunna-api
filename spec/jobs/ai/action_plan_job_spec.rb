require "rails_helper"

RSpec.describe Ai::ActionPlanJob do
  let(:company) { create(:company, :with_ai) }
  let(:account) { create(:ml_account, company: company) }
  let(:url) { "https://openrouter.ai/api/v1/chat/completions" }
  let!(:plan) { create(:ai_plan, ml_account: account, item_id: "MLB1", status: "pending") }

  before do
    create(:item_metric, ml_account: account, item_id: "MLB1", title: "Item A", status: "active", sku: "SKU-A",
      price: 100.0, stock: 10, visits_30d: 100, prev_visits_30d: 90, units_30d: 10, prev_units_30d: 8,
      revenue_30d: 1000.0, prev_revenue_30d: 800.0, fees_30d: 100.0, conversion_30d: 10.0)
    create(:ml_item, ml_account: account, item_id: "MLB1", price: 100.0)
  end

  def sse(*contents, finish: "stop")
    events = contents.map { |c| %(data: {"choices":[{"index":0,"delta":{"content":#{c.to_json}}}]}\n\n) }
    events << %(data: {"choices":[{"index":0,"delta":{},"finish_reason":"#{finish}"}]}\n\n)
    events << "data: [DONE]\n\n"
    events.join
  end

  it "gera o texto e termina como done" do
    stub_request(:post, url).to_return(status: 200, body: sse("Diagnóstico: ", "tudo certo."))

    described_class.perform_now(plan.id)

    expect(plan.reload).to have_attributes(status: "done", text: "Diagnóstico: tudo certo.", error: nil)
  end

  it "erro da OpenRouter vira status error com a mensagem" do
    stub_request(:post, url).to_return(status: 402, body: "{}")

    described_class.perform_now(plan.id)

    expect(plan.reload).to have_attributes(status: "error", error: "Sem créditos na OpenRouter.")
  end

  it "modelo que só raciocina (content vazio + finish_reason length) vira erro, nunca done vazio" do
    stub_request(:post, url).to_return(status: 200, body: sse("", "", finish: "length"))

    described_class.perform_now(plan.id)

    expect(plan.reload.status).to eq("error")
    expect(plan.error).to match(/gastou todo o limite de tokens raciocinando/)
    expect(plan.text).to eq("")
  end

  it "erro inesperado vira mensagem genérica (não vaza a exceção)" do
    allow(Abc::Report).to receive(:item_for_prompt).and_raise(RuntimeError, "boom")

    described_class.perform_now(plan.id)

    expect(plan.reload).to have_attributes(status: "error", error: "Não foi possível gerar o plano agora. Tente de novo.")
  end

  it "grava o texto parcial durante a geração (é o que o polling lê)" do
    stub_const("Ai::ActionPlanJob::SAVE_EVERY", 0)
    partials = []
    allow(Ai::ActionPlan).to receive(:stream) do |_company, _prompt, &block|
      block.call("Diag")
      partials << AiPlan.find(plan.id).text
      block.call("nóstico")
    end

    described_class.perform_now(plan.id)

    expect(partials).to eq([ "Diag" ])
    expect(plan.reload).to have_attributes(status: "done", text: "Diagnóstico")
  end

  it "Parar (cancelled) no meio interrompe e não é sobrescrito por done" do
    stub_const("Ai::ActionPlanJob::SAVE_EVERY", 0)
    allow(Ai::ActionPlan).to receive(:stream) do |_company, _prompt, &block|
      AiPlan.where(id: plan.id).update_all(status: "cancelled")
      block.call("a")
      block.call("b")
    end

    described_class.perform_now(plan.id)

    expect(plan.reload.status).to eq("cancelled")
  end

  it "plano que não está pending (ex.: cancelado antes de começar) não roda" do
    plan.update!(status: "cancelled")

    described_class.perform_now(plan.id)

    expect(WebMock).not_to have_requested(:post, url)
    expect(plan.reload.status).to eq("cancelled")
  end
end
