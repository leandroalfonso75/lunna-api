# Série de 15 dias (D−14..D) pro gráfico (SPEC 7.3): unidades pagas,
# faturamento, pedidos distintos e visitas, por dia, mais a escala dos
# eixos. Mesma regra de dia de pedido de Painel::ItemMetrics (DECISOES §1).
module Painel
  class Daily
    UNITS_STEP = 10
    VISITS_STEP = 500

    def self.call(account, today: Date.current) = new(account, today).call

    def initialize(account, today)
      @account = account
      @today = today
      @range = Painel::Periods.call(today)[:daily]
    end

    def call
      orders = orders_by_day
      visits = visits_by_day

      days = (@range.begin..@range.end).map do |day|
        o = orders[day] || { units: 0, revenue: 0, orders: 0 }
        { day: day.iso8601, units: o[:units], revenue: o[:revenue].to_f, orders: o[:orders],
          visits: visits[day].to_i, is_today: day == @today }
      end

      { daily: days, daily_scale: scale(days) }
    end

    private

    def scale(days)
      { units_max: ceil_to(days.map { |d| d[:units] }.max.to_i, UNITS_STEP),
        visits_max: ceil_to(days.map { |d| d[:visits] }.max.to_i, VISITS_STEP) }
    end

    def ceil_to(value, step)
      [ (value.to_f / step).ceil * step, step ].max
    end

    def orders_by_day
      sql = <<~SQL
        SELECT order_day, SUM(quantity) AS units, SUM(quantity * unit_price) AS revenue, COUNT(DISTINCT order_id) AS orders
        FROM (
          SELECT ml_order_items.order_id, ml_order_items.quantity, ml_order_items.unit_price,
                 (ml_orders.date_created AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS order_day
          FROM ml_order_items
          INNER JOIN ml_orders ON ml_orders.order_id = ml_order_items.order_id
          WHERE ml_orders.ml_account_id = :account_id AND ml_orders.status = 'paid'
        ) paid_order_items
        WHERE order_day BETWEEN :from AND :to
        GROUP BY order_day
      SQL

      binds = { account_id: @account.id, from: @range.begin, to: @range.end }
      rows = ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([ sql, binds ])).to_a

      rows.index_by { |row| row["order_day"] }
        .transform_values { |row| { units: row["units"], revenue: row["revenue"], orders: row["orders"] } }
    end

    def visits_by_day
      MlItemVisit.where(ml_account_id: @account.id, day: @range).group(:day).sum(:visits)
    end
  end
end
