# Agrega visitas e pedidos pagos por anúncio (SPEC 6, docs/METRICS.md) e
# regrava item_metrics inteira da conta. Chamado ao fim de cada sincronização
# (Ml::Sync::Run) e depois de PATCH /api/company (os cortes/percentuais da
# empresa não mudam as métricas em si, mas o A5 recalcula a Curva ABC em cima
# delas — o refresh aqui garante que a base está sempre fresca).
module Painel
  class ItemMetrics
    EMPTY_VISITS = { visits_7d: 0, prev_visits_7d: 0, visits_30d: 0, prev_visits_30d: 0 }.freeze
    EMPTY_ORDERS = {
      units_today: 0, units_7d: 0, prev_units_7d: 0, units_30d: 0, prev_units_30d: 0,
      revenue_7d: 0, prev_revenue_7d: 0, revenue_30d: 0, prev_revenue_30d: 0,
      net_after_fee_7d: 0, fees_30d: 0
    }.freeze
    LISTING_TYPES = { "gold_pro" => "P", "gold_special" => "C" }.freeze

    def self.refresh(account, today: Date.current) = new(account, today).refresh

    def initialize(account, today)
      @account = account
      @today = today
      @periods = Painel::Periods.call(today)
    end

    def refresh
      visits = visits_by_item
      orders = orders_by_item

      rows = @account.ml_items.find_each.map { |item| build_row(item, visits[item.item_id], orders[item.item_id]) }

      ItemMetric.transaction do
        ItemMetric.where(ml_account_id: @account.id).delete_all
        ItemMetric.insert_all(rows) if rows.any?
      end
    end

    private

    def build_row(item, visits, orders)
      visits ||= EMPTY_VISITS
      orders ||= EMPTY_ORDERS
      price = effective_price(item)

      {
        item_id: item.item_id,
        ml_account_id: @account.id,
        title: item.title,
        status: item.status,
        sku: item.sku,
        listing_type: LISTING_TYPES[item.listing_type_id],
        full: item.logistic_type == "fulfillment",
        free_shipping: item.free_shipping,
        catalog: item.catalog_listing,
        variations: item.variations_count,
        price: price,
        original_price: original_price(item, price),
        stock: item.available_quantity,
        quality_score: item.quality_score
      }.merge(visits).merge(orders).merge(
        conversion_7d: conversion(orders[:units_7d], visits[:visits_7d]),
        prev_conversion_7d: conversion(orders[:prev_units_7d], visits[:prev_visits_7d]),
        conversion_30d: conversion(orders[:units_30d], visits[:visits_30d]),
        prev_conversion_30d: conversion(orders[:prev_units_30d], visits[:prev_visits_30d]),
        units_delta: units_delta(orders[:units_7d], orders[:prev_units_7d]),
        coverage_days: coverage(item.available_quantity, orders[:units_7d], 7),
        coverage_30d: coverage(item.available_quantity, orders[:units_30d], 30),
        computed_at: Time.current
      )
    end

    # `sale_price` se existir e for diferente de `price`; senão `price`.
    def effective_price(item)
      return item.sale_price if item.sale_price.present? && item.sale_price != item.price

      item.price
    end

    # `original_price` do item; senão `regular_price` quando o preço de
    # venda é menor que ele; senão nil.
    def original_price(item, price)
      return item.original_price if item.original_price.present?
      return item.regular_price if item.regular_price.present? && price.present? && price < item.regular_price

      nil
    end

    def conversion(units, visits)
      return nil if visits.to_i.zero?

      (units.to_f / visits * 100).round(2)
    end

    # Nil se ninguém vendeu nem essa semana nem a anterior — variação só
    # existe pra quem teve venda em alguma das duas.
    def units_delta(units_7d, prev_units_7d)
      return nil if units_7d.to_i.zero? && prev_units_7d.to_i.zero?

      units_7d - prev_units_7d
    end

    def coverage(stock, units, days)
      return nil if units.to_i.zero?

      (stock.to_i / (units.to_f / days)).round(1)
    end

    def visits_by_item
      sql = <<~SQL
        SELECT item_id,
          SUM(CASE WHEN day BETWEEN :week_from AND :week_to THEN visits ELSE 0 END) AS visits_7d,
          SUM(CASE WHEN day BETWEEN :prev_week_from AND :prev_week_to THEN visits ELSE 0 END) AS prev_visits_7d,
          SUM(CASE WHEN day BETWEEN :month_from AND :month_to THEN visits ELSE 0 END) AS visits_30d,
          SUM(CASE WHEN day BETWEEN :prev_month_from AND :prev_month_to THEN visits ELSE 0 END) AS prev_visits_30d
        FROM ml_item_visits
        WHERE ml_account_id = :account_id
        GROUP BY item_id
      SQL

      execute(sql, period_binds).index_by { |row| row["item_id"] }.transform_values(&:symbolize_keys)
    end

    # Só pedidos `paid`, sempre via ml_orders da conta (DECISOES §2). `date_created`
    # é `timestamp without time zone` gravado em UTC (default_timezone :utc do
    # Rails); pra virar o dia civil em São Paulo (DECISOES §1) é preciso marcar
    # o valor como UTC antes de converter — só `AT TIME ZONE 'America/Sao_Paulo'`
    # direto trataria o valor como se já fosse hora local de SP, errando o dia
    # de quem compra à noite (ex.: pedido 23:30 em SP cairia no dia seguinte).
    def orders_by_item
      sql = <<~SQL
        SELECT item_id,
          SUM(CASE WHEN order_day = :today THEN quantity ELSE 0 END) AS units_today,
          SUM(CASE WHEN order_day BETWEEN :week_from AND :week_to THEN quantity ELSE 0 END) AS units_7d,
          SUM(CASE WHEN order_day BETWEEN :prev_week_from AND :prev_week_to THEN quantity ELSE 0 END) AS prev_units_7d,
          SUM(CASE WHEN order_day BETWEEN :month_from AND :month_to THEN quantity ELSE 0 END) AS units_30d,
          SUM(CASE WHEN order_day BETWEEN :prev_month_from AND :prev_month_to THEN quantity ELSE 0 END) AS prev_units_30d,
          SUM(CASE WHEN order_day BETWEEN :week_from AND :week_to THEN quantity * unit_price ELSE 0 END) AS revenue_7d,
          SUM(CASE WHEN order_day BETWEEN :prev_week_from AND :prev_week_to THEN quantity * unit_price ELSE 0 END) AS prev_revenue_7d,
          SUM(CASE WHEN order_day BETWEEN :month_from AND :month_to THEN quantity * unit_price ELSE 0 END) AS revenue_30d,
          SUM(CASE WHEN order_day BETWEEN :prev_month_from AND :prev_month_to THEN quantity * unit_price ELSE 0 END) AS prev_revenue_30d,
          SUM(CASE WHEN order_day BETWEEN :week_from AND :week_to THEN quantity * (unit_price - sale_fee) ELSE 0 END) AS net_after_fee_7d,
          SUM(CASE WHEN order_day BETWEEN :month_from AND :month_to THEN quantity * sale_fee ELSE 0 END) AS fees_30d
        FROM (
          SELECT ml_order_items.item_id, ml_order_items.quantity, ml_order_items.unit_price, ml_order_items.sale_fee,
                 (ml_orders.date_created AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS order_day
          FROM ml_order_items
          INNER JOIN ml_orders ON ml_orders.order_id = ml_order_items.order_id
          WHERE ml_orders.ml_account_id = :account_id AND ml_orders.status = 'paid'
        ) paid_order_items
        GROUP BY item_id
      SQL

      execute(sql, period_binds.merge(today: @today)).index_by { |row| row["item_id"] }.transform_values(&:symbolize_keys)
    end

    def period_binds
      {
        account_id: @account.id,
        week_from: @periods[:week].begin, week_to: @periods[:week].end,
        prev_week_from: @periods[:prev_week].begin, prev_week_to: @periods[:prev_week].end,
        month_from: @periods[:month].begin, month_to: @periods[:month].end,
        prev_month_from: @periods[:prev_month].begin, prev_month_to: @periods[:prev_month].end
      }
    end

    def execute(sql, binds)
      ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([ sql, binds ])).to_a
    end
  end
end
