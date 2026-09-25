require "rails_helper"

RSpec.describe Painel::Alerts do
  let(:account) { create(:ml_account) }
  let(:metrics) { account.item_metrics }

  it "só devolve alertas com count > 0, com item_ids" do
    create(:item_metric, ml_account: account, status: "active", stock: 0)

    result = described_class.call(metrics)

    expect(result.map { |a| a[:key] }).to eq([ "nostock" ])
    expect(result.first).to include(title: "Ativos sem estoque", severity: "bad", count: 1)
    expect(result.first[:item_ids]).to eq(metrics.pluck(:item_id))
  end

  describe "sales_drop: pu7 - u7 >= 3" do
    it "3 entra" do
      item = create(:item_metric, ml_account: account, status: "active", units_7d: 5, prev_units_7d: 8)
      expect(described_class.scope_for("sales_drop", metrics).pluck(:item_id)).to eq([ item.item_id ])
    end

    it "2 não entra" do
      create(:item_metric, ml_account: account, status: "active", units_7d: 6, prev_units_7d: 8)
      expect(described_class.scope_for("sales_drop", metrics)).to be_empty
    end
  end

  describe "low_coverage: cobertura < 14" do
    it "13.9 entra" do
      item = create(:item_metric, ml_account: account, status: "active", coverage_days: 13.9)
      expect(described_class.scope_for("low_coverage", metrics).pluck(:item_id)).to eq([ item.item_id ])
    end

    it "14 não entra" do
      create(:item_metric, ml_account: account, status: "active", coverage_days: 14)
      expect(described_class.scope_for("low_coverage", metrics)).to be_empty
    end

    it "ignora cobertura nil" do
      create(:item_metric, ml_account: account, status: "active", coverage_days: nil)
      expect(described_class.scope_for("low_coverage", metrics)).to be_empty
    end
  end

  describe "visits_no_sales: v7 >= 30 e u7 = 0" do
    it "30 entra" do
      item = create(:item_metric, ml_account: account, status: "active", visits_7d: 30, units_7d: 0)
      expect(described_class.scope_for("visits_no_sales", metrics).pluck(:item_id)).to eq([ item.item_id ])
    end

    it "29 não entra" do
      create(:item_metric, ml_account: account, status: "active", visits_7d: 29, units_7d: 0)
      expect(described_class.scope_for("visits_no_sales", metrics)).to be_empty
    end
  end

  describe "low_quality: nota < 70" do
    it "69 entra" do
      item = create(:item_metric, ml_account: account, status: "active", quality_score: 69)
      expect(described_class.scope_for("low_quality", metrics).pluck(:item_id)).to eq([ item.item_id ])
    end

    it "70 não entra" do
      create(:item_metric, ml_account: account, status: "active", quality_score: 70)
      expect(described_class.scope_for("low_quality", metrics)).to be_empty
    end
  end

  it "under_review e paused_selling" do
    create(:item_metric, ml_account: account, status: "under_review")
    create(:item_metric, ml_account: account, status: "paused", prev_units_7d: 1, units_7d: 0)

    result = described_class.call(metrics)

    expect(result.map { |a| a[:key] }).to match_array(%w[under_review paused_selling])
  end

  it "keys_by_item devolve as chaves de cada item, restrito ao relation recebido" do
    a = create(:item_metric, ml_account: account, status: "active", stock: 0)
    b = create(:item_metric, ml_account: account, status: "active", quality_score: 50)

    keys = described_class.keys_by_item(metrics.where(item_id: [ a.item_id ]))

    expect(keys[a.item_id]).to eq([ "nostock" ])
    expect(keys[b.item_id]).to eq([]) # fora do relation restrito
  end
end
