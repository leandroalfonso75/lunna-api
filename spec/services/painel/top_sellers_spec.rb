require "rails_helper"

RSpec.describe Painel::TopSellers do
  let(:account) { create(:ml_account) }
  let(:metrics) { account.item_metrics }

  it "só quem vendeu numa das duas semanas, ordenado por u7 e desempatado por pu7" do
    top = create(:item_metric, ml_account: account, title: "Top", units_7d: 10, prev_units_7d: 1)
    tie_a = create(:item_metric, ml_account: account, title: "Empate maior", units_7d: 5, prev_units_7d: 8)
    tie_b = create(:item_metric, ml_account: account, title: "Empate menor", units_7d: 5, prev_units_7d: 2)
    only_prev = create(:item_metric, ml_account: account, title: "Só semana anterior", units_7d: 0, prev_units_7d: 3)
    create(:item_metric, ml_account: account, title: "Não vendeu", units_7d: 0, prev_units_7d: 0)

    result = described_class.call(metrics)

    expect(result.map { |r| r[:id] }).to eq([ top.item_id, tie_a.item_id, tie_b.item_id, only_prev.item_id ])
  end

  it "limita a 10 e escala as barras pelo maior valor entre as linhas devolvidas" do
    12.times { |i| create(:item_metric, ml_account: account, units_7d: 12 - i, prev_units_7d: 1) }

    result = described_class.call(metrics)

    expect(result.size).to eq(10)
    expect(result.first[:bar_pct]).to eq(100.0) # maior valor (12) é a própria escala
    expect(result.first[:bar_prev_pct]).to eq((1.0 / 12 * 100).round(1))
  end
end
