require "rails_helper"

RSpec.describe Painel::ItemEconomics do
  let(:company) { create(:company, fixed_expenses_pct: 3) }
  let(:account) { create(:ml_account, company: company) }

  def metric(item_id: "MLB1", sku: "SKU-1", price: 100.0)
    create(:item_metric, ml_account: account, item_id: item_id, sku: sku, price: price)
  end

  def item(item_id: "MLB1", fee_now: 16.5, ship_cost: 8.0, fee_details: nil)
    create(:ml_item, ml_account: account, item_id: item_id, fee_now: fee_now, ship_cost: ship_cost, fee_details: fee_details)
  end

  def olist_cost(sku, value, **attrs)
    create(:olist_product, company: company, sku: sku, variation_kind: "N", status: "A", cost_price: value, avg_cost_price: 0, **attrs)
  end

  def call(*metrics) = described_class.for_page(account, metrics)

  it "lucro líquido = preço − custo − comissão − frete/taxas − despesas fixas (3%)" do
    m = metric
    item(fee_now: 16.5, ship_cost: 8.0)
    olist_cost("SKU-1", 40)

    result = call(m)[m.item_id]

    expect(result).to include(price: 100.0, cost: 40.0, cost_source: "cadastro", commission: 16.5, shipping_fees: 8.0,
      fixed_expenses: 3.0, fixed_expenses_pct: 3.0)
    expect(result[:net_profit]).to be_within(0.001).of(100 - 40 - 16.5 - 8 - 3)
    expect(result[:net_profit_pct]).to be_within(0.001).of(32.5)
  end

  it "separa comissão de taxa fixa e financiamento usando o detalhe da tarifa" do
    m = metric
    item(fee_now: 23.0, ship_cost: 10.0, fee_details: { "fixed_fee" => 6.0, "financing_add_on_fee" => 0.5, "percentage_fee" => 16.5, "gross_amount" => 23.0 })
    olist_cost("SKU-1", 30)

    result = call(m)[m.item_id]

    expect(result[:commission]).to be_within(0.001).of(16.5)
    expect(result[:shipping_fees]).to be_within(0.001).of(10 + 6 + 0.5)
    expect(result).to include(fees_split: true, fixed_fee: 6.0, financing: 0.5)
    expect(result[:net_profit]).to be_within(0.001).of(100 - 30 - 16.5 - 16.5 - 3)
  end

  it "sem o detalhe da tarifa, a tarifa inteira vale como comissão (e avisa que não foi separada)" do
    m = metric
    item(fee_now: 22.5, ship_cost: 0)
    olist_cost("SKU-1", 10)

    result = call(m)[m.item_id]

    expect(result).to include(commission: 22.5, fees_split: false, fees_known: true)
  end

  it "sem custo no Olist usa o custo manual do SKU (custo + extra)" do
    m = metric
    item
    MlCost.create!(company: company, sku: "SKU-1", cost: 30, extra: 5)

    result = call(m)[m.item_id]

    expect(result).to include(cost: 35.0, cost_source: "manual")
  end

  it "o Olist tem prioridade sobre o custo manual" do
    m = metric
    item
    olist_cost("SKU-1", 20)
    MlCost.create!(company: company, sku: "SKU-1", cost: 99, extra: 0)

    expect(call(m)[m.item_id]).to include(cost: 20.0, cost_source: "cadastro")
  end

  it "sem custo em lugar nenhum: custo e lucro ficam vazios, o resto é calculado" do
    m = metric
    item

    result = call(m)[m.item_id]

    expect(result).to include(cost: nil, cost_source: nil, net_profit: nil, net_profit_pct: nil, commission: 16.5)
  end

  it "usa a % de despesas fixas da empresa" do
    company.update!(fixed_expenses_pct: 5)
    m = metric
    item(fee_now: 0, ship_cost: 0)
    olist_cost("SKU-1", 0.01)

    expect(call(m)[m.item_id]).to include(fixed_expenses: 5.0, fixed_expenses_pct: 5.0)
  end

  it "prejuízo aparece negativo" do
    m = metric(price: 30)
    item(fee_now: 10, ship_cost: 15)
    olist_cost("SKU-1", 20)

    result = call(m)[m.item_id]

    expect(result[:net_profit]).to be < 0
    expect(result[:net_profit_pct]).to be < 0
  end

  it "anúncio sem SKU: sem custo do Olist" do
    m = metric(sku: nil)
    item

    expect(call(m)[m.item_id]).to include(cost: nil)
  end

  it "anúncio sem preço não tem resultado" do
    m = metric(price: nil)
    item

    expect(call(m)[m.item_id]).to be_nil
  end

  it "sem tarifa conhecida marca fees_known como falso" do
    m = metric
    item(fee_now: nil, ship_cost: 4)
    olist_cost("SKU-1", 10)

    expect(call(m)[m.item_id]).to include(fees_known: false, commission: 0.0, shipping_fees: 4.0)
  end
end
