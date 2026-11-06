# Seção Vendas: lista de pedidos do Mercado Livre com filtros, busca, ordenação, paginação,
# totais e série diária. Tudo resolvido aqui (regra na API; o front só exibe).
#
# Lucro líquido do pedido (mesma conta de Anúncios, ver Painel::ItemEconomics):
#   receita − custo − tarifa de venda − frete pago pelo vendedor − despesas fixas − imposto
# Frete do carrinho: vendas do mesmo carrinho (pack) viajam no MESMO envio e o ML informa o frete do
# envio inteiro em cada uma. O frete do vendedor é dividido entre as vendas do envio, proporcional às
# unidades de cada uma (as canceladas ficam de fora).
# Custo de Ads (lucro pós Ads): o gasto de publicidade de cada anúncio no período escolhido (ml_ad_item_dailies, da
# seção Ads) é dividido entre as unidades vendidas desse anúncio no mesmo período (cobre também o gasto de dias sem
# venda, que costuma virar venda indireta dias depois). O gasto de anúncios que não venderam nada no período aparece à
# parte no resumo ("Ads sem venda") e sai do lucro pós Ads, para o total bater com a seção Ads. Dia da venda ainda
# não fechado na leitura de Ads (hoje, ou lido antes de acabar) deixa a venda "pendente": refeita até fechar.
# Pedido cancelado não entra nos totais. Sem custo de algum item, o lucro do pedido não é calculado.
module Painel
  class SalesQuery
    # "mtd" = mês até hoje (do dia 1º do mês corrente até hoje); os demais são dias corridos até hoje
    PRESETS = { "today" => 1, "yesterday" => 1, "7d" => 7, "mtd" => 31, "30d" => 30, "60d" => 60, "90d" => 90 }.freeze
    DEFAULT_PERIOD = "30d"
    MAX_DAYS = 92
    PER_PAGES = [ 25, 50, 100 ].freeze
    SORTS = %w[date total profit profit_pct units ads_cost profit_after_ads profit_after_ads_pct].freeze

    ORDER_STATUS = {
      "paid" => [ "Paga", "ok" ], "confirmed" => [ "Confirmada", "neutral" ],
      "payment_required" => [ "Aguardando pagamento", "warn" ], "payment_in_process" => [ "Pagamento em análise", "warn" ],
      "partially_paid" => [ "Parcialmente paga", "warn" ], "cancelled" => [ "Cancelada", "bad" ],
      "invalid" => [ "Inválida", "bad" ], "partially_refunded" => [ "Reembolso parcial", "warn" ]
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
                      buyer_id buyer_nickname shipment shipment_synced_at claims
                      buyer_name buyer_doc_type buyer_doc_number buyer_city buyer_state billing_synced_at].freeze
    # motivo do cancelamento sem carregar o payload inteiro do pedido na lista
    CANCEL_DETAIL = Arel.sql("payload->'cancel_detail' AS cancel_detail")

    def self.call(account, params, reveal_doc: false)
      new(account, params, reveal_doc: reveal_doc).call
    end

    # params: o mesmo período da lista (period ou from/to), que define o rateio do custo de Ads.
    def self.detail(account, order_id, params = {}, reveal_doc: false)
      new(account, params, reveal_doc: reveal_doc).detail(order_id)
    end

    # reveal_doc: administrador vê o CPF/CNPJ inteiro; os demais, mascarado.
    def initialize(account, params, reveal_doc: false)
      @account = account
      @company = account.company
      @params = params
      @reveal_doc = reveal_doc
      @zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
    end

    def call
      from, to = window
      base = @account.ml_orders.where(date_created: from..to)
      scope = apply_filters(base)

      rows = build_rows(scope.select(*LIST_COLUMNS, CANCEL_DETAIL).to_a)
      sorted = sort(rows)
      page, per = paging
      slice = sorted.slice((page - 1) * per, per) || []
      attach_carts!(slice)

      {
        period: { from: from.iso8601, to: to.iso8601, preset: preset_key, month: month_key },
        months: available_months,
        summary: summary(rows, filtered: filtered?),
        daily: daily(rows, from, to),
        counts: counts(base),
        sales: slice,
        total: sorted.size, page: page, per_page: per,
        sort: sort_key, dir: sort_dir,
        sync: sync_info
      }
    end

    # Seção Financeiro: todas as vendas de uma janela (a do filtro ou outra, ex.: o período anterior), com a mesma conta
    # da lista e os mesmos filtros, sem paginação. O rateio de Ads segue a janela pedida.
    def period_rows(from = nil, to = nil)
      @window_override = [ from, to ] if from && to
      from, to = window
      rows = build_rows(apply_filters(@account.ml_orders.where(date_created: from..to)).select(*LIST_COLUMNS, CANCEL_DETAIL).to_a)
      { from: from, to: to, rows: rows, summary: summary(rows, filtered: filtered?), daily: daily(rows, from, to) }
    ensure
      @window_override = nil
    end

    def current_window = window

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
        buyer: row[:buyer].merge(id: order.buyer_id, nickname: order.buyer_nickname),
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
      ads = ads_context(orders, items)
      billed = billed_shipping(orders)
      @coupons = coupons(orders)

      orders.map do |order|
        row(order, items[order.order_id] || [], olist, manual, thumbs, groups[order.shipping_id], ads, billed[order.shipping_id])
      end
    end

    # Frete cobrado pelo ML no extrato de faturamento (tarifas de envio menos cancelamentos), por envio, só para
    # conferência (Financeiro › conciliação). O custo da venda continua o de /shipments/{id}/costs: quando o comprador
    # paga parte do frete, o ML cobra do vendedor a etiqueta cheia (list_cost) e o valor do comprador entra no
    # pagamento da venda; cobrado = previsto + parte do comprador (conferido em 217 de 217 casos em 06/11/2026).
    SHIPPING_CODES = %w[CFFE CXDE CFFI].freeze

    # Cupom com participação do vendedor: o Mercado Pago desconta a parte do vendedor (coupon_fee) no pagamento da
    # venda. seller = custo do vendedor (entra no lucro); total = desconto dado ao comprador no cupom.
    COUPON_STATUSES = %w[approved in_mediation authorized].freeze

    def coupons(orders)
      ids = orders.map(&:order_id)
      return {} if ids.empty?

      @account.mp_payments.where(order_id: ids, status: COUPON_STATUSES).where("description IS DISTINCT FROM 'marketplace_shipment'")
        .where("coupon_amount <> 0 OR charges @> '[{\"type\":\"coupon\"}]'")
        .to_a.group_by(&:order_id).transform_values do |pays|
          total = pays.sum { |p| Array(p.charges).select { |c| c["type"] == "coupon" && c["from"] != "collector" }.sum { |c| c["amount"].to_f - c["refunded"].to_f } }
          { seller: pays.sum { |p| p.coupon_amount.to_f }.round(2), total: total.round(2) }
        end
    end

    def billed_shipping(orders)
      ids = orders.filter_map(&:shipping_id).uniq
      return {} if ids.empty?

      @account.ml_billing_charges.where(shipment_id: ids).to_a
        .select { |r| SHIPPING_CODES.include?(r.detail_sub_type.to_s.sub(/\AB/, "C")) }
        .group_by(&:shipment_id).transform_values { |rows| rows.sum(&:signed_amount).round(2) }
        .select { |_, net| net.positive? }
    end

    # --- custo de Ads por venda ---

    def sale_day(order) = order.date_created.in_time_zone(@zone).to_date

    def ads_days
      from, to = window
      from.in_time_zone(@zone).to_date..to.in_time_zone(@zone).to_date
    end

    # Tudo o que o rateio precisa, buscado uma vez para a página inteira: gasto e unidades de cada anúncio no período.
    def ads_context(orders, items)
      lines = items.values.flatten
      item_ids = lines.map(&:item_id).uniq
      active = orders.reject { |o| %w[cancelled invalid].include?(o.status) }
      return { empty: true } if active.empty? || item_ids.empty?

      days = active.map { |o| sale_day(o) }.uniq
      spend = MlAdItemDaily.where(ml_account_id: @account.id, item_id: item_ids, date: ads_days).group(:item_id).sum(:cost)
        .transform_values(&:to_f)
      closed = @account.ml_ad_day_syncs.where(date: days).to_h { |s| [ s.date, s.closed? ] }
      advertised = MlAdItem.where(ml_account_id: @account.id, item_id: item_ids).pluck(:item_id).to_set
      advertised.merge(MlAdItemDaily.where(ml_account_id: @account.id, item_id: item_ids).distinct.pluck(:item_id))

      { spend: spend, closed: closed, advertised: advertised, units: units_sold_by_item(item_ids) }
    end

    # Unidades vendidas por anúncio no período (vendas não canceladas, sem os filtros da tela): base do rateio.
    def units_sold_by_item(item_ids = nil)
      from, to = window
      scope = MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
        .where(o: { ml_account_id: @account.id }).where.not(o: { status: %w[cancelled invalid] })
        .where("o.date_created BETWEEN ? AND ?", from, to)
      scope = scope.where(item_id: item_ids) if item_ids
      scope.group("ml_order_items.item_id").sum("ml_order_items.quantity")
    end

    # Gasto de Ads no período que não vai para venda nenhuma: anúncios que não venderam nenhuma unidade nele, mais a
    # diferença entre o gasto das campanhas (o total da seção Ads) e a soma por anúncio, quando o ML não detalha tudo.
    def ads_unsold
      sold = units_sold_by_item.select { |_, units| units.to_i.positive? }.keys
      items = MlAdItemDaily.where(ml_account_id: @account.id, date: ads_days)
      campaigns = @account.ml_ad_daily_metrics.where(date: ads_days).sum(:cost).to_f
      items.where.not(item_id: sold).sum(:cost).to_f + [ campaigns - items.sum(:cost).to_f, 0.0 ].max
    end

    # => { cost:, state: "apurado" | "pendente" | "sem_ads", lines: [...] }
    def ads_for(order, lines, ads)
      return { cost: 0.0, state: "sem_ads", lines: [] } if ads[:empty]

      pending = !ads[:closed][sale_day(order)]
      line_costs = lines.filter_map do |line|
        next unless ads[:advertised].include?(line.item_id)

        period_cost = ads[:spend][line.item_id].to_f
        sold = ads[:units][line.item_id].to_i
        share = sold.positive? ? period_cost * line.quantity.to_i / sold : 0.0
        { item_id: line.item_id, period_cost: period_cost, period_units: sold, cost: share }
      end

      state = line_costs.empty? ? "sem_ads" : (pending ? "pendente" : "apurado")
      { cost: line_costs.sum(0.0) { |l| l[:cost] }, state: state, lines: line_costs }
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

    def row(order, lines, olist, manual, thumbs, group, ads, billed = nil)
      shipment = order.shipment
      shipment = shipment.merge("seller_cost_billed" => billed) if shipment && billed
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
        buyer: buyer(order, shipment),
        items: items, units: items.sum { |i| i[:quantity].to_i },
        total_amount: order.total_amount&.to_f, paid_amount: order.paid_amount&.to_f,
        shipping: shipping(order, shipment, share, group, order.order_id),
        issue: SaleIssues.for(order),
        economics: economics(order, lines, shipment, olist, manual, share, ads)
      }
    end

    # Coluna "Cliente": nome, documento (CPF/CNPJ) e cidade/UF (do faturamento, que traz a sigla da UF; sem ele, do envio).
    def buyer(order, shipment)
      city = [ order.buyer_city, order.buyer_state ].compact_blank
      city = [ shipment&.dig("destination_city"), shipment&.dig("destination_state") ].compact_blank if city.empty?
      { name: order.buyer_name, doc_type: order.buyer_doc_type, doc: format_doc(order.buyer_doc_type, order.buyer_doc_number),
        city: city.join("/").presence, loaded: order.billing_synced_at.present? }
    end

    # CPF 123.456.789-01 / CNPJ 12.345.678/0001-90; para quem não é administrador, só os 3 do meio do CPF
    # (***.456.789-**) e o CNPJ inteiro (é de empresa).
    def format_doc(type, number)
      return nil if number.blank?

      if number.size == 11
        return "***.#{number[3, 3]}.#{number[6, 3]}-**" unless @reveal_doc

        "#{number[0, 3]}.#{number[3, 3]}.#{number[6, 3]}-#{number[9, 2]}"
      elsif number.size == 14
        "#{number[0, 2]}.#{number[2, 3]}.#{number[5, 3]}/#{number[8, 4]}-#{number[12, 2]}"
      else
        @reveal_doc ? number : "#{'*' * [ number.size - 4, 0 ].max}#{number[-4..]}"
      end
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
        seller_cost_billed: shipment["seller_cost_billed"]&.to_f,
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

    def economics(order, lines, shipment, olist, manual, shipping_cost_share, ads)
      return nil if %w[cancelled invalid].include?(order.status) || lines.empty?

      revenue = lines.sum { |l| l.unit_price.to_f * l.quantity.to_i }
      fee = lines.sum { |l| l.sale_fee.to_f * l.quantity.to_i }
      shipping_cost = shipping_cost_share.to_f
      tax = revenue * @company.tax_pct.to_f / 100.0
      fixed = revenue * @company.fixed_expenses_pct.to_f / 100.0
      cost = total_cost(lines, olist, manual)
      coupon = (@coupons || {})[order.order_id] || {}
      coupon_cost = coupon[:seller].to_f
      profit = cost.nil? ? nil : revenue - cost - fee - shipping_cost - coupon_cost - fixed - tax
      ads_info = ads_for(order, lines, ads)
      after_ads = profit.nil? ? nil : profit - ads_info[:cost]

      {
        revenue: revenue, cost: cost, fee: fee, shipping_cost: shipping_cost,
        shipping_known: shipment.present? && !shipment["seller_cost"].nil?,
        coupon_cost: coupon_cost, coupon_discount: coupon[:total].to_f,
        fixed_expenses: fixed, tax: tax,
        net_profit: profit, net_profit_pct: profit && revenue.positive? ? profit / revenue * 100.0 : nil,
        ads_cost: ads_info[:cost], ads_state: ads_info[:state], ads_lines: ads_info[:lines],
        net_profit_after_ads: after_ads,
        net_profit_after_ads_pct: after_ads && revenue.positive? ? after_ads / revenue * 100.0 : nil
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

    def filtered? = %i[status shipping logistic q].any? { |key| @params[key].to_s.strip.present? }

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
      return "month" if month_key

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

    # Filtro por mês ("2026-10"): do dia 1º ao último dia (o mês atual vai até hoje). Só meses da lista.
    def month_key
      key = @params[:month].to_s
      available_months.any? { |m| m[:value] == key } ? key : nil
    end

    # Mês atual primeiro e os anteriores em ordem decrescente, até o mês do limite de 92 dias (o mais antigo fica
    # parcial: começa no limite).
    def available_months
      @available_months ||= begin
        first = data_start
        months = []
        month = @zone.today.beginning_of_month
        while month >= first.beginning_of_month
          months << { value: month.strftime("%Y-%m"), label: month.strftime("%m/%Y"), current: month == @zone.today.beginning_of_month,
                      partial: month < first }
          month = month.prev_month
        end
        months
      end
    end

    # Início dos dados: os últimos 92 dias que a sincronização diária mantém, ou antes, quando há vendas antigas
    # importadas (até 13 meses).
    MAX_HISTORY_DAYS = 400

    def data_start
      @data_start ||= begin
        oldest = @account.ml_orders.minimum(:date_created)&.in_time_zone(@zone)&.to_date
        recent = @zone.today - MAX_DAYS
        [ [ oldest || recent, recent ].min, @zone.today - MAX_HISTORY_DAYS ].max
      end
    end

    def window
      return @window_override if @window_override

      limit = data_start
      if (key = month_key)
        start = Date.strptime(key, "%Y-%m")
        first = [ start, limit ].max
        last = [ start.end_of_month, @zone.today ].min
        return [ first.in_time_zone(@zone).beginning_of_day, last == @zone.today ? @zone.now.end_of_day : last.in_time_zone(@zone).end_of_day ]
      end
      if custom_dates?
        first = [ parse_date(@params[:from]), limit ].max
        last = [ parse_date(@params[:to]), @zone.today ].min
        last = first if last < first
        return [ @zone.local(first.year, first.month, first.day).beginning_of_day, @zone.local(last.year, last.month, last.day).end_of_day ]
      end

      if preset_key == "yesterday"
        day = (@zone.today - 1).in_time_zone(@zone)
        return [ day.beginning_of_day, day.end_of_day ]
      end
      return [ @zone.today.beginning_of_month.in_time_zone(@zone).beginning_of_day, @zone.now.end_of_day ] if preset_key == "mtd"

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
        when "ads_cost" then r.dig(:economics, :ads_cost)
        when "profit_after_ads" then r.dig(:economics, :net_profit_after_ads)
        when "profit_after_ads_pct" then r.dig(:economics, :net_profit_after_ads_pct)
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

    # Pedidos do mesmo carrinho (pack_id com 2+ pedidos), sem olhar filtros nem página: cada linha ganha
    # `cart: { pack_id, size, position, order_ids }` para a lista indicar que pertencem à mesma venda; `nil` fora disso.
    def attach_carts!(rows)
      packs = rows.filter_map { |r| r[:pack_id] }.uniq
      groups = packs.empty? ? {} : @account.ml_orders.where(pack_id: packs).order(:date_created, :order_id).pluck(:pack_id, :order_id)
        .group_by(&:first).transform_values { |list| list.map(&:last) }
      rows.each do |r|
        ids = groups[r[:pack_id]]
        r[:cart] = ids && ids.size > 1 ? { pack_id: r[:pack_id], size: ids.size, position: ids.index(r[:order_id]).to_i + 1, order_ids: ids } : nil
      end
    end

    # Uma venda = um carrinho do ML (pack_id) quando houver, senão o pedido. Carrinho com 2 produtos são 2 pedidos no
    # ML e 1 venda no Olist e na tela de vendas do ML; a lista continua por pedido.
    def sales_count(rows) = rows.map { |r| r[:pack_id] || r[:order_id] }.uniq.size

    # filtered: com filtro ou busca na tela, o gasto de anúncios sem venda não tem como ser atribuído e fica de fora.
    def summary(rows, filtered: false)
      active = rows.select { |r| r[:economics] }
      known = active.select { |r| r[:economics][:net_profit] }
      revenue = active.sum { |r| r[:economics][:revenue] }
      profit = known.sum { |r| r[:economics][:net_profit] }
      known_revenue = known.sum { |r| r[:economics][:revenue] }
      ads_cost = active.sum { |r| r[:economics][:ads_cost] }
      unsold = filtered ? nil : ads_unsold
      after_ads = known.sum { |r| r[:economics][:net_profit_after_ads] } - unsold.to_f

      {
        orders: sales_count(active), units: active.sum { |r| r[:units] },
        cancelled: sales_count(rows - active),
        revenue: revenue, ticket: active.empty? ? nil : revenue / sales_count(active),
        fee: active.sum { |r| r[:economics][:fee] },
        shipping_cost: active.sum { |r| r[:economics][:shipping_cost] },
        coupon_cost: active.sum { |r| r[:economics][:coupon_cost].to_f },
        coupon_discount: active.sum { |r| r[:economics][:coupon_discount].to_f },
        coupon_orders: active.count { |r| r[:economics][:coupon_discount].to_f.positive? || r[:economics][:coupon_cost].to_f.positive? },
        tax: active.sum { |r| r[:economics][:tax] },
        fixed_expenses: active.sum { |r| r[:economics][:fixed_expenses] },
        cost: known.sum { |r| r[:economics][:cost] },
        net_profit: profit, net_profit_pct: known_revenue.positive? ? profit / known_revenue * 100.0 : nil,
        ads_cost: ads_cost + unsold.to_f, ads_cost_sales: ads_cost, ads_unsold: unsold,
        net_profit_after_ads: after_ads,
        net_profit_after_ads_pct: known_revenue.positive? ? after_ads / known_revenue * 100.0 : nil,
        orders_ads_pending: active.count { |r| r[:economics][:ads_state] == "pendente" },
        orders_without_cost: active.size - known.size,
        orders_without_shipment: active.count { |r| !r[:shipping][:loaded] && r[:shipping][:label] == "Carregando…" }
      }
    end

    def daily(rows, from, to)
      by_day = rows.select { |r| r[:economics] }.group_by { |r| r[:date_created].in_time_zone(@zone).to_date }
      (from.to_date..to.to_date).map do |day|
        list = by_day[day] || []
        { date: day.iso8601, orders: sales_count(list), units: list.sum { |r| r[:units] },
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
