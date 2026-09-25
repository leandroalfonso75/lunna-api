require "rails_helper"

RSpec.describe Painel::Kpis do
  let(:account) { create(:ml_account) }
  let(:metrics) { account.item_metrics }
  let(:daily) { [ { day: "2026-09-24", units: 3, revenue: 150.0, orders: 2, visits: 10, is_today: true } ] }

  it "monta os seis cartões, na ordem da SPEC 7.2" do
    create(:item_metric, ml_account: account, status: "active", units_7d: 10, prev_units_7d: 8,
      revenue_7d: 500, prev_revenue_7d: 400, visits_7d: 100, prev_visits_7d: 80, stock: 20, full: true)

    cards = described_class.call(metrics, daily)

    expect(cards.map { |c| c[:key] }).to eq(%w[today units_7d revenue_7d visits_7d conversion_7d stock_active])
  end

  it "'hoje até agora' vem do daily, sem delta" do
    card = described_class.call(metrics, daily).first

    expect(card).to include(value: 150.0, value_type: "money", sub_label: "3 un. · 2 pedidos", delta: nil)
  end

  it "delta em % pra vendas/faturado/visitas, direção flat/up/down" do
    create(:item_metric, ml_account: account, status: "active", units_7d: 11, prev_units_7d: 10) # +10%

    card = described_class.call(metrics, daily)[1]

    expect(card[:value]).to eq(11)
    expect(card[:delta]).to eq(value: 10.0, unit: "pct", direction: "up")
  end

  it "sem valor anterior (0), delta vem nil" do
    create(:item_metric, ml_account: account, status: "active", units_7d: 5, prev_units_7d: 0)

    card = described_class.call(metrics, daily)[1]

    expect(card[:delta]).to be_nil
  end

  it "direção flat quando |delta| < 0.5" do
    create(:item_metric, ml_account: account, status: "active", units_7d: 100, prev_units_7d: 100) # 0%

    card = described_class.call(metrics, daily)[1]

    expect(card[:delta][:direction]).to eq("flat")
  end

  it "conversão em pontos percentuais, não em %" do
    create(:item_metric, ml_account: account, status: "active", units_7d: 20, visits_7d: 100, prev_units_7d: 10, prev_visits_7d: 100)

    card = described_class.call(metrics, daily)[4]

    expect(card[:value]).to eq(20.0) # 20/100*100
    expect(card[:delta]).to eq(value: 10.0, unit: "pp", direction: "up") # 20 - 10
  end

  it "estoque dos ativos soma só os ativos e mostra quantos estão no Full" do
    create(:item_metric, ml_account: account, status: "active", stock: 10, full: true)
    create(:item_metric, ml_account: account, status: "active", stock: 5, full: false)
    create(:item_metric, ml_account: account, status: "paused", stock: 999, full: true)

    card = described_class.call(metrics, daily).last

    expect(card).to include(key: "stock_active", value: 15, sub_label: "1 anúncios no Full", delta: nil)
  end
end
