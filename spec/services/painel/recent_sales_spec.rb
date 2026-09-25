require "rails_helper"

RSpec.describe Painel::RecentSales do
  let(:account) { create(:ml_account) }

  it "as 10 vendas pagas mais recentes, com título do anúncio e total = preço × quantidade" do
    item = create(:ml_item, ml_account: account, item_id: "MLB1", title: "Anúncio com título")

    old_order = MlOrder.create!(order_id: 1, ml_account: account, status: "paid", date_created: 2.days.ago, total_amount: 10, synced_at: Time.current)
    MlOrderItem.create!(order_id: old_order.order_id, item_id: item.item_id, quantity: 1, unit_price: 50, sale_fee: 1)

    recent_order = MlOrder.create!(order_id: 2, ml_account: account, status: "paid", date_created: 1.hour.ago, total_amount: 10, synced_at: Time.current)
    MlOrderItem.create!(order_id: recent_order.order_id, item_id: item.item_id, quantity: 3, unit_price: 20, sale_fee: 1)

    cancelled = MlOrder.create!(order_id: 3, ml_account: account, status: "cancelled", date_created: 1.minute.ago, total_amount: 10, synced_at: Time.current)
    MlOrderItem.create!(order_id: cancelled.order_id, item_id: item.item_id, quantity: 9, unit_price: 9, sale_fee: 1)

    result = described_class.call(account)

    expect(result.size).to eq(2)
    expect(result.first).to include(item_id: "MLB1", title: "Anúncio com título", quantity: 3, total: 60.0)
    expect(result.last[:quantity]).to eq(1)
  end

  it "sem o anúncio na conta, o título cai pro próprio item_id" do
    order = MlOrder.create!(order_id: 1, ml_account: account, status: "paid", date_created: Time.current, total_amount: 10, synced_at: Time.current)
    MlOrderItem.create!(order_id: order.order_id, item_id: "MLB-SUMIU", quantity: 1, unit_price: 10, sale_fee: 1)

    result = described_class.call(account)

    expect(result.first).to include(item_id: "MLB-SUMIU", title: "MLB-SUMIU")
  end

  it "não traz vendas de outra conta" do
    other_account = create(:ml_account)
    order = MlOrder.create!(order_id: 1, ml_account: other_account, status: "paid", date_created: Time.current, total_amount: 10, synced_at: Time.current)
    MlOrderItem.create!(order_id: order.order_id, item_id: "MLB-OUTRA", quantity: 1, unit_price: 10, sale_fee: 1)

    expect(described_class.call(account)).to eq([])
  end
end
