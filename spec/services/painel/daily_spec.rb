require "rails_helper"

RSpec.describe Painel::Daily do
  let(:account) { create(:ml_account) }
  let(:today) { Date.new(2026, 9, 24) }

  def sp_time(date, hour) = Time.zone.local(date.year, date.month, date.day, hour)

  it "monta os 15 dias (D-14..D) com unidades, faturamento, pedidos distintos e visitas" do
    item = create(:ml_item, ml_account: account, item_id: "MLB1", price: 10)

    order = MlOrder.create!(order_id: 1, ml_account: account, status: "paid", date_created: sp_time(today - 1, 10), total_amount: 20, synced_at: Time.current)
    MlOrderItem.create!(order_id: order.order_id, item_id: item.item_id, quantity: 2, unit_price: 10, sale_fee: 1)

    other_order = MlOrder.create!(order_id: 2, ml_account: account, status: "paid", date_created: sp_time(today - 1, 14), total_amount: 10, synced_at: Time.current)
    MlOrderItem.create!(order_id: other_order.order_id, item_id: item.item_id, quantity: 1, unit_price: 10, sale_fee: 1)

    MlItemVisit.create!(item_id: item.item_id, ml_account: account, day: today - 1, visits: 12)

    result = described_class.call(account, today: today)

    expect(result[:daily].size).to eq(15)
    expect(result[:daily].first[:day]).to eq((today - 14).iso8601)
    expect(result[:daily].last[:day]).to eq(today.iso8601)
    expect(result[:daily].last[:is_today]).to be true

    day = result[:daily].find { |d| d[:day] == (today - 1).iso8601 }
    expect(day[:units]).to eq(3)
    expect(day[:revenue]).to eq(30.0)
    expect(day[:orders]).to eq(2) # 2 pedidos distintos
    expect(day[:visits]).to eq(12)
  end

  it "escala em múltiplos de 10 (unidades) e 500 (visitas), com mínimo 10/500" do
    item = create(:ml_item, ml_account: account, item_id: "MLB1", price: 10)
    order = MlOrder.create!(order_id: 1, ml_account: account, status: "paid", date_created: sp_time(today, 10), total_amount: 10, synced_at: Time.current)
    MlOrderItem.create!(order_id: order.order_id, item_id: item.item_id, quantity: 23, unit_price: 10, sale_fee: 1)
    MlItemVisit.create!(item_id: item.item_id, ml_account: account, day: today, visits: 1200)

    result = described_class.call(account, today: today)

    expect(result[:daily_scale]).to eq(units_max: 30, visits_max: 1500)
  end

  it "sem nenhum dado, a escala cai no mínimo (10/500)" do
    result = described_class.call(account, today: today)

    expect(result[:daily_scale]).to eq(units_max: 10, visits_max: 500)
  end
end
