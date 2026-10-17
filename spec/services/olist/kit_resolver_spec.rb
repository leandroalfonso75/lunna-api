require "rails_helper"

RSpec.describe Olist::KitResolver do
  let(:company) { create(:company) }

  def part(olist_id, sku, **attrs)
    create(:olist_product, company: company, olist_id: olist_id, sku: sku, variation_kind: "N", status: "A", cost_price: 0, avg_cost_price: 0, **attrs)
  end

  def kit(olist_id, sku, components, **attrs)
    create(:olist_product, company: company, olist_id: olist_id, sku: sku, kind: "K", variation_kind: "N", status: "A",
      kit_components: components.map { |id, sku_c, qty| { "id" => id, "sku" => sku_c, "quantity" => qty } }, **attrs)
  end

  def resolve(*kits) = described_class.for_kits(company, kits)

  it "custo do kit = soma de quantidade × custo de cada componente" do
    part(1, "A", fifo_unit_cost: 95.3, stock_available: 161)
    part(2, "B", cost_price: 11, stock_available: 1826)
    k = kit(10, "KIT", [ [ 1, "A", 1 ], [ 2, "B", 3 ] ])

    result = resolve(k)[10]

    expect(result.unit_cost).to eq(95.3 + 33.0)
    expect(result.missing_cost).to eq([])
    expect(result.components.map { |c| [ c[:sku], c[:quantity], c[:unit_cost], c[:cost_source], c[:subtotal] ] }).to eq(
      [ [ "A", 1.0, 95.3, "peps", 95.3 ], [ "B", 3.0, 11.0, "cadastro", 33.0 ] ]
    )
  end

  it "estoque do kit = menor quantidade de kits que os componentes permitem (arredondando para baixo)" do
    part(1, "A", stock_available: 161, cost_price: 1)
    part(2, "B", stock_available: 10, cost_price: 1)
    k = kit(10, "KIT", [ [ 1, "A", 1 ], [ 2, "B", 3 ] ])

    expect(resolve(k)[10].available).to eq(3) # 10 ÷ 3 = 3,33 → 3 (A permitiria 161)
  end

  it "componente sem custo: o custo do kit fica vazio e lista os SKUs" do
    part(1, "A", cost_price: 5, stock_available: 10)
    part(2, "B", stock_available: 10)
    k = kit(10, "KIT", [ [ 1, "A", 1 ], [ 2, "B", 1 ] ])

    result = resolve(k)[10]

    expect(result.unit_cost).to be_nil
    expect(result.missing_cost).to eq([ "B" ])
    expect(result.available).to eq(10)
  end

  it "componente que não está na base: sem estoque nem custo calculados" do
    part(1, "A", cost_price: 5, stock_available: 10)
    k = kit(10, "KIT", [ [ 1, "A", 1 ], [ 99, "FANTASMA", 1 ] ])

    result = resolve(k)[10]

    expect(result.complete).to be false
    expect(result.available).to be_nil
    expect(result.unit_cost).to be_nil
    expect(result.missing_cost).to eq([ "FANTASMA" ])
  end

  it "componente com estoque negativo derruba o estoque do kit" do
    part(1, "A", cost_price: 1, stock_available: -3)
    part(2, "B", cost_price: 1, stock_available: 10)
    k = kit(10, "KIT", [ [ 1, "A", 1 ], [ 2, "B", 1 ] ])

    expect(resolve(k)[10].available).to eq(-3)
  end

  it "ignora produtos que não são kit ou ainda sem composição lida" do
    part(1, "A", cost_price: 5)
    sem_composicao = create(:olist_product, company: company, olist_id: 20, sku: "K2", kind: "K", kit_components: [])

    expect(resolve(sem_composicao)).to eq({})
    expect(resolve(OlistProduct.find_by(olist_id: 1))).to eq({})
  end

  it "não usa produtos de outra empresa como componente" do
    other = create(:olist_product, olist_id: 1, sku: "A", cost_price: 9, stock_available: 5)
    k = kit(10, "KIT", [ [ other.olist_id, "A", 1 ] ])

    result = resolve(k)[10]

    expect(result.complete).to be false
  end
end
