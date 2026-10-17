# Seção Vendas: lista de pedidos do Mercado Livre com filtros, busca, ordenação, paginação,
# totais e série diária. Tudo resolvido aqui (regra na API; o front só exibe).
#
# Lucro líquido do pedido (mesma conta de Anúncios, ver Painel::ItemEconomics):
#   receita − custo − tarifa de venda − frete pago pelo vendedor − despesas fixas − imposto
# Frete do carrinho: vendas do mesmo carrinho (pack) viajam no MESMO envio e o ML informa o frete do
# envio inteiro em cada uma. O frete do vendedor é dividido entre as vendas do envio, proporcional às
# unidades de cada uma (as canceladas ficam de fora).
# Pedido cancelado não entra nos totais. Sem custo de algum item, o lucro do pedido não é calculado.
module Painel
  class SalesQuery
    PRESETS = { "7d" => 7, "30d" => 30, "60d" => 60, "90d" => 90 }.freeze
    DEFAULT_PERIOD = "30d"
    MAX_DAYS = 92
    PER_PAGES = [ 25, 50, 100 ].freeze
    SORTS = %w[date total profit profit_pct units].freeze

    ORDER_STATUS = {
      "paid" => [ "Paga", "ok" ], "confirmed" => [ "Confirmada", "neutral" ],
      "payment_required" => [ "Aguardando pagamento", "warn" ], "payment_in_process" => [ "Pagamento em análise", "warn" ],
      "partially_paid" => [ "Parcialmente paga", "warn" ], "cancelled" => [ "Cancelada", "bad" ],
      "invalid" => [ "Inválida", "bad" ]
    }.freeze

    SHIPMENT_STATUS = {
      "pending" => [ "Pendente", "warn" ], "handling" => [ "Em preparação", "warn" ],
      "ready_to_ship" => [ "Pronto para enviar", "warn" ], "shipped" => [ "A caminho", "neutral" ],
      "delivered" => [ "Entregue", "ok" ], "not_delivered" => [ "Não entregue", "bad" ],
      "cancelled" => [ "Envio cancelado", "bad" ], "returned" => [ "Devolvido", "bad" ],
      "to_be_agreed" => [ "A combinar", "neutral" ], "unavailable" => [ "Sem dados de envio", "neutral" ]
    }.freeze

    LOGISTICS = {
      "fulfillment" => "Full", "self_service" => "Flex", "cross_docking" => "Coleta",
      "xd_drop_off" => "Agência", "drop_off" => "Agência", "default" => "Envio padrão", "custom" => "Envio próprio"
    }.freeze

    SHIPPING_GROUPS = {
      "preparing" => %w[pending handling ready_to_ship],
      "transit" => %w[shipped],
      "delivered" => %w[delivered],
      "problem" => %w[not_delivered cancelled returned]
    }.freeze

    LOGISTIC_GROUPS = {
      "full" => %w[fulfillment], "flex" => %w[self_service], "coleta" => %w[cross_docking],
      "agencia" => %w[xd_drop_off drop_off]
    }.freeze

    LIST_COLUMNS = %i[order_id ml_account_id status date_created date_closed total_amount paid_amount shipping_id pack_id
                      buyer_id buyer_nickname shipment shipment_synced_at].freeze

    def self.call(account, params)
      new(account, params).call
    end

    def self.detail(account, order_id)
      new(account, {}).detail(order_id)
    end

    def initialize(account, params)
      @account = account
      @company = account.company
      @params = params
      @zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
    end

    def call
      from, to = window
      base = @account.ml_orders.where(date_created: from..to)
      scope = apply_filters(base)

      rows = build_rows(scope.select(*LIST_COLUMNS).to_a)
      sorted = sort(rows)
      page, per = paging
      slice = sorted.slice((page - 1) * per, per) || []

      {
        period: { from: from.iso8601, to: to.iso8601, preset: preset_key },
        summary: summary(rows),
        daily: daily(rows, from, to),
        counts: counts(base),
        sales: slice,
        total: sorted.size, page: page, per_page: per,
        sort: sort_key, dir: sort_dir,
        sync: sync_info
      }
    end

    def detail(order_id)
      order = @account.ml_orders.includes(:ml_order_items).find_by!(order_id: order_id)
      row = build_rows([ order ]).first
      payload = order.payload || {}

      row.merge(
        payments: Array(payload["payments"]).map { |p| payment(p) },
        items_detail: Array(payload["order_items"]).map { |line| item_detail(line) },
        tags: payload["tags"],
        coupon_amount: payload.dig("coupon", "amount"),
        date_last_updated: payload["date_last_updated"],
        expiration_date: payload["expiration_date"],
        buyer: { id: order.buyer_id, nickname: order.buyer_nickname },
        shipment_detail: row[:shipping]
      )
    end

    private

    def build_rows(orders)
      items = MlOrderItem.where(order_id: orders.map(&:order_id)).group_by(&:order_id)
      skus = items.values.flatten.map(&:sku).compact_blank.uniq
      olist = Olist::UnitCost.for_skus(@company, skus)
      manual = @company.ml_costs.where(sku: skus).index_by(&:sku)
      thumbs = @account.ml_items.where(item_id: items.values.flatten.map(&:item_id).uniq).pluck(:item_id, :thumbnail).to_h
      groups = shipment_groups(orders)

      orders.map { |order| row(order, items[order.order_id] || [], olist, manual, thumbs, groups[order.shipping_id]) }
    end

    # shipping_id => { units: total de unidades das vendas ativas do envio, orders: [order_id, ...] }
    def shipment_groups(orders)
      ids = orders.filter_map(&:shipping_id).uniq
      return {} if ids.empty?

      rows = @account.ml_orders.where(shipping_id: ids).where.not(status: %w[cancelled invalid])
        .joins("JOIN ml_order_items i ON i.order_id = ml_orders.order_id")
        .group("ml_orders.shipping_id", "ml_orders.order_id").sum("i.quantity")

      rows.each_with_object({}) do |((shipping_id, order_id), quantity), groups|
        group = groups[shipping_id] ||= { units: 0, orders: [] }
        group[:units] += quantity.to_i
        group[:orders] << order_id
      end
    end

    def row(order, lines, olist, manual, thumbs, group)
      shipment = order.shipment
      units = lines.sum { |line| line.quantity.to_i }
      share = shipping_share(shipment, units, group)
      items = lines.map do |line|
        { item_id: line.item_id, title: line.title, sku: line.sku, quantity: line.quantity,
          unit_price: line.unit_price&.to_f, sale_fee: line.sale_fee&.to_f,
          listing_type: line.listing_type_id, thumbnail: thumbs[line.item_id] }
      end

      {
        order_id: order.order_id, pack_id: order.pack_id,
        date_created: order.date_created, date_closed: order.date_closed,
        status: status_label(ORDER_STATUS, order.status), buyer_nickname: order.buyer_nickname,
        items: items, units: items.sum { |i| i[:quantity].to_i },
        total_amount: order.total_amount&.to_f, paid_amount: order.paid_amount&.to_f,
        shipping: shipping(order, shipment, share, group, order.order_id),
        economics: economics(order, lines, shipment, olist, manual, share)
      }
    end

    # Parte desta venda no frete do vendedor do envio: frete × unidades da venda ÷ unidades do envio.
    def shipping_share(shipment, units, group)
      cost = shipment&.dig("seller_cost")
      return nil if cost.nil?
      return cost.to_f if group.nil? || group[:orders].size < 2 || group[:units].zero?

      cost.to_f * units / group[:units]
    end

    def shipping(order, shipment, share = nil, group = nil, order_id = nil)
      return { status: nil, label: order.shipping_id ? "Carregando…" : "Sem envio", tone: "neutral", loaded: false } if shipment.blank?

      status, tone = SHIPMENT_STATUS.fetch(shipment["status"], [ shipment["status"].to_s, "neutral" ])
      history = shipment["status_history"] || {}
      {
        id: order.shipping_id, status: shipment["status"], label: status, tone: tone, loaded: true,
        substatus: shipment["substatus"], logistic_type: shipment["logistic_type"],
        logistic_label: LOGISTICS.fetch(shipment["logistic_type"], shipment["logistic_type"]),
        method_name: shipment["method_name"], tracking_number: shipment["tracking_number"],
        seller_cost: shipment["seller_cost"]&.to_f, seller_cost_share: share,
        shared_with: group ? (group[:orders] - [ order_id ]) : [],
        buyer_cost: shipment["buyer_cost"]&.to_f,
        list_cost: shipment["list_cost"]&.to_f,
        destination: [ shipment["destination_city"], shipment["destination_state"] ].compact.join(" / ").presence,
        estimated_delivery: shipment["estimated_delivery"],
        dates: {
          handling: history["date_handling"], ready_to_ship: history["date_ready_to_ship"],
          shipped: history["date_shipped"], delivered: history["date_delivered"],
          cancelled: history["date_cancelled"], returned: history["date_returned"]
        },
        history: Array(shipment["substatus_history"]).map { |h| { date: h["date"], status: h["status"], substatus: h["substatus"] } }
      }
    end

    def economics(order, lines, shipment, olist, manual, shipping_cost_share)
      return nil if %w[cancelled invalid].include?(order.status) || lines.empty?

      revenue = lines.sum { |l| l.unit_price.to_f * l.quantity.to_i }
      fee = lines.sum { |l| l.sale_fee.to_f * l.quantity.to_i }
      shipping_cost = shipping_cost_share.to_f
      tax = revenue * @company.tax_pct.to_f / 100.0
      fixed = revenue * @company.fixed_expenses_pct.to_f / 100.0
      cost = total_cost(lines, olist, manual)
      profit = cost.nil? ? nil : revenue - cost - fee - shipping_cost - fixed - tax

      {
        revenue: revenue, cost: cost, fee: fee, shipping_cost: shipping_cost,
        shipping_known: shipment.present? && !shipment["seller_cost"].nil?,
        fixed_expenses: fixed, tax: tax,
        net_profit: profit, net_profit_pct: profit && revenue.positive? ? profit / revenue * 100.0 : nil
      }
    end

    def total_cost(lines, olist, manual)
      total = 0.0
      lines.each do |line|
        unit = olist[line.sku]&.value&.to_f || (manual[line.sku] && manual[line.sku].cost.to_f + manual[line.sku].extra.to_f)
        return nil if unit.nil?

        total += unit * line.quantity.to_i
      end
      total
    end

    def status_label(table, key)
      label, tone = table.fetch(key, [ key.to_s, "neutral" ])
      { key: key, label: label, tone: tone }
    end

    def payment(p)
      { id: p["id"], status: p["status"], method: p["payment_method_id"], type: p["payment_type"],
        installments: p["installments"], total_paid: p["total_paid_amount"], transaction_amount: p["transaction_amount"],
        refunded: p["transaction_amount_refunded"], shipping_cost: p["shipping_cost"], taxes: p["taxes_amount"],
        coupon: p["coupon_amount"], date_approved: p["date_approved"] }
    end

    def item_detail(line)
      { item_id: line.dig("item", "id"), title: line.dig("item", "title"), sku: line.dig("item", "seller_sku"),
        category_id: line.dig("item", "category_id"), condition: line.dig("item", "condition"),
        warranty: line.dig("item", "warranty"), variation_id: line.dig("item", "variation_id"),
        variation: Array(line.dig("item", "variation_attributes")).map { |a| "#{a["name"]}: #{a["value_name"]}" },
        quantity: line["quantity"], unit_price: line["unit_price"], full_unit_price: line["full_unit_price"],
        sale_fee: line["sale_fee"], listing_type: line["listing_type_id"] }
    end

    # --- filtros ---

    def apply_filters(scope)
      scope = scope.where(status: status_filter) if status_filter

      if (statuses = SHIPPING_GROUPS[@params[:shipping].to_s])
        scope = scope.where("shipment->>'status' IN (?)", statuses)
      elsif @params[:shipping].to_s == "none"
        scope = scope.where(shipping_id: nil)
      end

      if (types = LOGISTIC_GROUPS[@params[:logistic].to_s])
        scope = scope.where("shipment->>'logistic_type' IN (?)", types)
      elsif @params[:logistic].to_s == "other"
        scope = scope.where("shipment IS NOT NULL AND COALESCE(shipment->>'logistic_type','') NOT IN (?)", LOGISTIC_GROUPS.values.flatten)
      end

      apply_search(scope)
    end

    def status_filter
      case @params[:status].to_s
      when "paid" then "paid"
      when "cancelled" then %w[cancelled invalid]
      end
    end

    def apply_search(scope)
      q = @params[:q].to_s.strip
      return scope if q.empty?

      like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      scope.where(
        "ml_orders.order_id::text = :q OR ml_orders.pack_id::text = :q OR ml_orders.buyer_nickname ILIKE :like OR " \
        "ml_orders.shipment->>'tracking_number' = :q OR EXISTS (SELECT 1 FROM ml_order_items i WHERE i.order_id = ml_orders.order_id " \
        "AND (i.title ILIKE :like OR i.sku ILIKE :like OR i.item_id ILIKE :like))",
        q: q, like: like
      )
    end

    # --- período ---

    def preset_key
      key = @params[:period].to_s
      return "custom" if custom_dates?

      PRESETS.key?(key) ? key : DEFAULT_PERIOD
    end

    def custom_dates?
      parse_date(@params[:from]) && parse_date(@params[:to])
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def window
      limit = @zone.today - MAX_DAYS
      if custom_dates?
        first = [ parse_date(@params[:from]), limit ].max
        last = [ parse_date(@params[:to]), @zone.today ].min
        last = first if last < first
        return [ @zone.local(first.year, first.month, first.day).beginning_of_day, @zone.local(last.year, last.month, last.day).end_of_day ]
      end

      days = PRESETS.fetch(preset_key)
      [ (@zone.today - (days - 1)).in_time_zone(@zone).beginning_of_day, @zone.now.end_of_day ]
    end

    # --- ordenação e paginação ---

    def sort_key = SORTS.include?(@params[:sort].to_s) ? @params[:sort].to_s : "date"
    def sort_dir = @params[:dir].to_s == "asc" ? "asc" : "desc"

    def sort(rows)
      key = sort_key
      sorted = rows.sort_by do |r|
        value = case key
        when "date" then r[:date_created].to_f
        when "total" then r[:total_amount].to_f
        when "units" then r[:units].to_f
        when "profit" then r.dig(:economics, :net_profit)
        when "profit_pct" then r.dig(:economics, :net_profit_pct)
        end
        # sem valor vai sempre para o fim, nos dois sentidos
        [ value.nil? ? 1 : 0, sort_dir == "asc" ? (value || 0) : -(value || 0) ]
      end
      sorted
    end

    def paging
      per = @params[:per_page].to_i
      per = 50 unless PER_PAGES.include?(per)
      [ [ @params[:page].to_i, 1 ].max, per ]
    end

    # --- totais ---

    def summary(rows)
      active = rows.select { |r| r[:economics] }
      known = active.select { |r| r[:economics][:net_profit] }
      revenue = active.sum { |r| r[:economics][:revenue] }
      profit = known.sum { |r| r[:economics][:net_profit] }
      known_revenue = known.sum { |r| r[:economics][:revenue] }

      {
        orders: active.size, units: active.sum { |r| r[:units] },
        cancelled: rows.size - active.size,
        revenue: revenue, ticket: active.empty? ? nil : revenue / active.size,
        fee: active.sum { |r| r[:economics][:fee] },
        shipping_cost: active.sum { |r| r[:economics][:shipping_cost] },
        tax: active.sum { |r| r[:economics][:tax] },
        fixed_expenses: active.sum { |r| r[:economics][:fixed_expenses] },
        cost: known.sum { |r| r[:economics][:cost] },
        net_profit: profit, net_profit_pct: known_revenue.positive? ? profit / known_revenue * 100.0 : nil,
        orders_without_cost: active.size - known.size,
        orders_without_shipment: active.count { |r| !r[:shipping][:loaded] && r[:shipping][:label] == "Carregando…" }
      }
    end

    def daily(rows, from, to)
      by_day = rows.select { |r| r[:economics] }.group_by { |r| r[:date_created].in_time_zone(@zone).to_date }
      (from.to_date..to.to_date).map do |day|
        list = by_day[day] || []
        { date: day.iso8601, orders: list.size, units: list.sum { |r| r[:units] },
          revenue: list.sum { |r| r[:economics][:revenue] },
          net_profit: list.sum { |r| r[:economics][:net_profit].to_f } }
      end
    end

    # contagens para as abas/filtros, sobre o período inteiro (ignora os filtros)
    def counts(base)
      shipments = base.group(Arel.sql("COALESCE(shipment->>'status', 'none')")).count
      {
        status: base.group(:status).count,
        shipping: SHIPPING_GROUPS.transform_values { |list| list.sum { |s| shipments[s].to_i } }
          .merge("none" => base.where(shipping_id: nil).count),
        logistic: logistic_counts(base)
      }
    end

    def logistic_counts(base)
      by_type = base.where.not(shipment: nil).group(Arel.sql("shipment->>'logistic_type'")).count
      groups = LOGISTIC_GROUPS.transform_values { |list| list.sum { |t| by_type[t].to_i } }
      groups.merge("other" => by_type.except(*LOGISTIC_GROUPS.values.flatten).values.sum)
    end

    def sync_info
      {
        pending_shipments: Ml::Sync::Shipments.pending(@account, since: window.first).count,
        last_order_sync_at: @account.ml_orders.maximum(:synced_at)
      }
    end
  end
end
