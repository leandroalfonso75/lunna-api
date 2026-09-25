require "rails_helper"

RSpec.describe Painel::ItemMetrics do
  let(:account) { create(:ml_account) }
  let(:today) { Date.new(2026, 9, 24) }
  let(:order_seq) { (1..).each }

  def paid_order!(account, item_id, quantity:, unit_price:, at:, status: "paid")
    id = order_seq.next
    order = MlOrder.create!(order_id: id, ml_account: account, status: status, date_created: at,
      date_closed: at, total_amount: unit_price * quantity, synced_at: Time.current)
    MlOrderItem.create!(order_id: order.order_id, item_id: item_id, quantity: quantity, unit_price: unit_price, sale_fee: 1.5)
    order
  end

  def visit!(account, item_id, day:, visits:)
    MlItemVisit.create!(item_id: item_id, ml_account: account, day: day, visits: visits)
  end

  def sp_time(date, hour, min = 0) = Time.zone.local(date.year, date.month, date.day, hour, min)

  it "agrega visitas e vendas pagas por janela e calcula conversão, variação e cobertura" do
    item = create(:ml_item, ml_account: account, item_id: "MLB1", status: "active", price: 100,
      available_quantity: 14, quality_score: 90, listing_type_id: "gold_pro", logistic_type: "fulfillment")

    paid_order!(account, item.item_id, quantity: 3, unit_price: 100, at: sp_time(today - 7, 10))
    paid_order!(account, item.item_id, quantity: 3, unit_price: 100, at: sp_time(today - 3, 10))
    paid_order!(account, item.item_id, quantity: 2, unit_price: 100, at: sp_time(today - 10, 10))

    visit!(account, item.item_id, day: today - 1, visits: 40)
    visit!(account, item.item_id, day: today - 10, visits: 20)

    described_class.refresh(account, today: today)
    metric = ItemMetric.find(item.item_id)

    expect(metric.units_7d).to eq(6)
    expect(metric.prev_units_7d).to eq(2)
    expect(metric.revenue_7d.to_f).to eq(600.0)
    expect(metric.visits_7d).to eq(40)
    expect(metric.prev_visits_7d).to eq(20)
    expect(metric.conversion_7d.to_f).to eq(15.0) # 6 / 40 * 100
    expect(metric.units_delta).to eq(4) # 6 - 2
    expect(metric.coverage_days.to_f).to eq(16.3) # 14 / (6 / 7.0), arredondado
    expect(metric.full).to be true
    expect(metric.listing_type).to eq("P")
  end

  it "D-7 entra na semana atual e D-8 entra na semana anterior" do
    item = create(:ml_item, ml_account: account, item_id: "MLB2", price: 10)

    paid_order!(account, item.item_id, quantity: 1, unit_price: 10, at: sp_time(today - 7, 12))
    paid_order!(account, item.item_id, quantity: 1, unit_price: 10, at: sp_time(today - 8, 12))

    described_class.refresh(account, today: today)
    metric = ItemMetric.find(item.item_id)

    expect(metric.units_7d).to eq(1)
    expect(metric.prev_units_7d).to eq(1)
  end

  it "pedido às 23:30 de São Paulo cai no dia certo (não vaza pro dia seguinte em UTC)" do
    item = create(:ml_item, ml_account: account, item_id: "MLB3", price: 10)

    # 23:30 de D-7 em SP; em UTC isso já é madrugada de D-6.
    paid_order!(account, item.item_id, quantity: 5, unit_price: 10, at: sp_time(today - 7, 23, 30))

    described_class.refresh(account, today: today)
    metric = ItemMetric.find(item.item_id)

    expect(metric.units_7d).to eq(5) # continua dentro da semana (D-7..D-1)
  end

  it "pedido cancelado não entra nas métricas" do
    item = create(:ml_item, ml_account: account, item_id: "MLB4", price: 10)

    paid_order!(account, item.item_id, quantity: 3, unit_price: 10, at: sp_time(today - 1, 10), status: "cancelled")

    described_class.refresh(account, today: today)
    metric = ItemMetric.find(item.item_id)

    expect(metric.units_7d).to eq(0)
    expect(metric.revenue_7d.to_f).to eq(0.0)
  end

  it "não mistura pedidos e visitas de outra conta" do
    item = create(:ml_item, ml_account: account, item_id: "MLB5", price: 10)
    other_account = create(:ml_account)
    other_item = create(:ml_item, ml_account: other_account, item_id: "MLB5-OTHER", price: 10)

    paid_order!(other_account, other_item.item_id, quantity: 9, unit_price: 10, at: sp_time(today - 1, 10))
    visit!(other_account, other_item.item_id, day: today - 1, visits: 99)

    described_class.refresh(account, today: today)

    expect(ItemMetric.where(ml_account_id: account.id).pluck(:item_id)).to eq([ item.item_id ])
    expect(ItemMetric.find(item.item_id).units_7d).to eq(0)
  end

  it "units_delta e coverage_days ficam nil sem venda nas janelas relevantes" do
    item = create(:ml_item, ml_account: account, item_id: "MLB6", price: 10, available_quantity: 20)

    described_class.refresh(account, today: today)
    metric = ItemMetric.find(item.item_id)

    expect(metric.units_delta).to be_nil
    expect(metric.coverage_days).to be_nil
    expect(metric.coverage_30d).to be_nil
    expect(metric.conversion_7d).to be_nil
  end

  it "regrava a tabela inteira da conta a cada chamada (delete_all + insert_all)" do
    create(:ml_item, ml_account: account, item_id: "MLB7", price: 10)
    described_class.refresh(account, today: today)
    expect(ItemMetric.where(ml_account_id: account.id).count).to eq(1)

    described_class.refresh(account, today: today)
    expect(ItemMetric.where(ml_account_id: account.id).count).to eq(1)
  end
end
