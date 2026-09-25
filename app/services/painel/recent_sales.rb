# As 10 linhas de pedido pagas mais recentes (SPEC 7.6). Título vem de
# ml_items da conta; sem o anúncio (ex.: apagado), cai pro próprio item_id.
module Painel
  class RecentSales
    LIMIT = 10

    def self.call(account) = new(account).call

    def initialize(account)
      @account = account
    end

    def call
      lines = MlOrderItem.joins("INNER JOIN ml_orders ON ml_orders.order_id = ml_order_items.order_id")
        .where(ml_orders: { ml_account_id: @account.id, status: "paid" })
        .order(Arel.sql("ml_orders.date_created DESC"))
        .limit(LIMIT)
        .pluck(Arel.sql("ml_orders.date_created"), :item_id, :quantity, :unit_price)

      titles = @account.ml_items.where(item_id: lines.map { |line| line[1] }).pluck(:item_id, :title).to_h

      lines.map do |at, item_id, quantity, unit_price|
        {
          at: at, item_id: item_id, title: titles[item_id] || item_id,
          quantity: quantity, total: (unit_price * quantity).round(2).to_f
        }
      end
    end
  end
end
