require "rails_helper"

RSpec.describe Olist::FullStock do
  let(:company) { create(:company) }
  let(:account) { create(:ml_account, company: company) }

  def full_item(item_id, sku, refs, **attrs)
    create(:ml_item, ml_account: account, item_id: item_id, sku: sku, logistic_type: "fulfillment", status: "active", inventory_refs: refs, **attrs)
  end

  def stock(inventory_id, available:, not_available: 0, acct: account)
    MlFullStock.create!(ml_account: acct, inventory_id: inventory_id, available_units: available,
      not_available_units: not_available, total_units: available + not_available, synced_at: Time.current)
  end

  it "liga o estoque Full ao produto pelo SKU" do
    full_item("MLB1", "SKU-A", [ { "sku" => "SKU-A", "inventory_id" => "INV-A" } ])
    stock("INV-A", available: 9, not_available: 3)

    info = described_class.for_skus(company, [ "SKU-A", "SEM-FULL" ])

    expect(info.keys).to eq([ "SKU-A" ])
    expect(info["SKU-A"]).to have_attributes(available: 9, not_available: 3, total: 12, listings: 1)
  end

  it "um inventory compartilhado por dois anúncios do mesmo SKU conta uma vez" do
    full_item("MLB1", "SKU-A", [ { "sku" => "SKU-A", "inventory_id" => "INV-A" } ])
    full_item("MLB2", "SKU-A", [ { "sku" => "SKU-A", "inventory_id" => "INV-A" } ])
    stock("INV-A", available: 5)

    expect(described_class.for_skus(company, [ "SKU-A" ])["SKU-A"].available).to eq(5)
  end

  it "soma inventories diferentes do mesmo SKU" do
    full_item("MLB1", "SKU-A", [ { "sku" => "SKU-A", "inventory_id" => "INV-1" } ])
    full_item("MLB2", "SKU-A", [ { "sku" => "SKU-A", "inventory_id" => "INV-2" } ])
    stock("INV-1", available: 5)
    stock("INV-2", available: 7)

    expect(described_class.for_skus(company, [ "SKU-A" ])["SKU-A"].available).to eq(12)
  end

  it "anúncio com variações: cada variação liga ao próprio SKU" do
    full_item("MLB3", "VAR-1", [
      { "sku" => "VAR-1", "inventory_id" => "INV-V1" },
      { "sku" => "VAR-2", "inventory_id" => "INV-V2" }
    ])
    stock("INV-V1", available: 2)
    stock("INV-V2", available: 8)

    info = described_class.for_skus(company, [ "VAR-1", "VAR-2" ])

    expect(info["VAR-1"].available).to eq(2)
    expect(info["VAR-2"].available).to eq(8)
  end

  it "sem estoque lido ainda, o SKU não aparece" do
    full_item("MLB1", "SKU-A", [ { "sku" => "SKU-A", "inventory_id" => "INV-A" } ])

    expect(described_class.for_skus(company, [ "SKU-A" ])).to eq({})
  end

  it "não usa anúncios de outra empresa nem os que não são Full" do
    other_account = create(:ml_account)
    create(:ml_item, ml_account: other_account, item_id: "MLBX", sku: "SKU-A", logistic_type: "fulfillment", status: "active",
      inventory_refs: [ { "sku" => "SKU-A", "inventory_id" => "INV-X" } ])
    stock("INV-X", available: 99, acct: other_account)
    create(:ml_item, ml_account: account, item_id: "MLBY", sku: "SKU-A", logistic_type: "drop_off", status: "active",
      inventory_refs: [ { "sku" => "SKU-A", "inventory_id" => "INV-Y" } ])
    stock("INV-Y", available: 50)

    expect(described_class.for_skus(company, [ "SKU-A" ])).to eq({})
  end

  it "lista vazia ou SKUs em branco" do
    expect(described_class.for_skus(company, [])).to eq({})
    expect(described_class.for_skus(company, [ nil, "" ])).to eq({})
  end
end
