require "rails_helper"

RSpec.describe Olist::UnitCost do
  let(:company) { create(:company) }

  def product(sku, **attrs)
    create(:olist_product, company: company, sku: sku, variation_kind: "N", status: "A", cost_price: 0, avg_cost_price: 0, **attrs)
  end

  it "prefere o custo PEPS" do
    product("A", fifo_unit_cost: 7.5, cost_price: 9, avg_cost_price: 8)

    result = described_class.for_skus(company, [ "A" ])["A"]

    expect(result).to have_attributes(value: 7.5, source: "peps")
  end

  it "sem PEPS, usa o custo cadastrado no produto" do
    product("A", cost_price: 9, avg_cost_price: 8)

    expect(described_class.for_skus(company, [ "A" ])["A"]).to have_attributes(value: 9, source: "cadastro")
  end

  it "sem PEPS, sem custo cadastrado e sem custo médio, usa o custo da última entrada com preço" do
    product("A", fifo_last_entry_cost: 17.89)

    expect(described_class.for_skus(company, [ "A" ])["A"]).to have_attributes(value: 17.89, source: "ultima_entrada")
  end

  it "sem PEPS e sem custo cadastrado, usa o custo médio" do
    product("A", avg_cost_price: 8)

    expect(described_class.for_skus(company, [ "A" ])["A"]).to have_attributes(value: 8, source: "custo_medio")
  end

  it "produto sem nenhum custo não aparece" do
    product("A")

    expect(described_class.for_skus(company, [ "A" ])).to eq({})
  end

  it "ignora excluídos, pais de variação e produtos de outra empresa" do
    product("A", cost_price: 5, status: "E")
    product("B", cost_price: 5, variation_kind: "P")
    create(:olist_product, sku: "C", cost_price: 5, status: "A")

    expect(described_class.for_skus(company, %w[A B C])).to eq({})
  end

  it "com SKU repetido, usa o produto alterado mais recentemente" do
    product("A", cost_price: 1, olist_updated_at: 2.days.ago)
    product("A", cost_price: 2, olist_updated_at: 1.hour.ago)

    expect(described_class.for_skus(company, [ "A" ])["A"].value).to eq(2)
  end

  it "kit: custo = soma do custo dos componentes (fonte kit)" do
    a = product("A", fifo_unit_cost: 95.3)
    b = product("B", cost_price: 11)
    create(:olist_product, company: company, sku: "KIT", kind: "K", variation_kind: "N", status: "A", cost_price: 0, avg_cost_price: 0,
      kit_components: [ { "id" => a.olist_id, "sku" => "A", "quantity" => 1 }, { "id" => b.olist_id, "sku" => "B", "quantity" => 1 } ])

    expect(described_class.for_skus(company, [ "KIT" ])["KIT"]).to have_attributes(value: 106.3, source: "kit")
  end

  it "kit com componente sem custo não tem custo" do
    a = product("A", cost_price: 5)
    b = product("B")
    create(:olist_product, company: company, sku: "KIT", kind: "K", variation_kind: "N", status: "A", cost_price: 77,
      kit_components: [ { "id" => a.olist_id, "sku" => "A", "quantity" => 1 }, { "id" => b.olist_id, "sku" => "B", "quantity" => 1 } ])

    expect(described_class.for_skus(company, [ "KIT" ])).to eq({})
  end

  it "lista vazia ou SKUs em branco" do
    expect(described_class.for_skus(company, [])).to eq({})
    expect(described_class.for_skus(company, [ nil, "" ])).to eq({})
  end
end
