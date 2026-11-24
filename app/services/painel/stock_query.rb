# Seção Estoque (pedido do usuário em 14/11/2026), duas abas:
#   depot — estoque do depósito (Olist, estoque geral) por SKU: disponível, reservado, Full, total, custo unitário (PEPS ou
#           custo do cadastro), valor parado, vendas dos últimos 30 dias (ML, pelo SKU), cobertura em dias e o que o ML
#           pede para mandar ao Full;
#   full  — recomendações de reposição do Full (ml_full_replenishments): urgência, quantidade sugerida, prazo, vendas,
#           dias sem estoque nas últimas 6 semanas e receita perdida estimada; cruzado com o disponível no Olist para dizer
#           quanto dá para enviar já e quanto falta comprar.
# Kits não têm estoque próprio no Olist e ficam fora do depósito. Somente leitura.
module Painel
  class StockQuery
    PER_PAGE = 50
    LOW_COVERAGE_DAYS = 15
    ZONE = ActiveSupport::TimeZone["America/Sao_Paulo"]

    def self.depot(account, params) = new(account, params).depot
    def self.full(account, params) = new(account, params).full

    def initialize(account, params)
      @account = account
      @company = account.company
      @params = params
    end

    # --- aba Depósito (ERP) ---

    def depot
      products = @company.olist_products.where(hidden_at: nil).where.not(sku: [ nil, "" ]).where.not(kind: "K")
                         .where.not(variation_kind: "P").where.not(status: "E").to_a
      skus = products.map(&:sku)
      # kits (ex.: secador + difusor) vendem e ficam no Full com SKU próprio: a venda e o estoque Full do kit contam para
      # cada componente, na quantidade do kit
      kits = @company.olist_products.where(kind: "K").where.not(sku: [ nil, "" ]).where.not(kit_components: nil).to_a
      by_id = @company.olist_products.where(olist_id: kits.flat_map { |k| Array(k.kit_components).map { |c| c["id"] } }).pluck(:olist_id, :sku).to_h
      parts = kits.to_h { |k| [ k.sku, Array(k.kit_components).filter_map { |c| (sku = c["sku"].presence || by_id[c["id"]]) && [ sku, c["quantity"].to_f ] } ] }
      full_raw = Olist::FullStock.for_skus(@company, skus + parts.keys)
      sold_raw = units_sold(skus + parts.keys)
      full = Hash.new { |h, k| h[k] = { available: 0, not_available: 0, linked: false } }
      sold = Hash.new(0.0)
      full_raw.each do |sku, info|
        targets = parts[sku] || [ [ sku, 1.0 ] ]
        targets.each do |s, q|
          full[s][:available] += (info.available * q).to_i
          full[s][:not_available] += (info.not_available * q).to_i
          full[s][:linked] = true
        end
      end
      sold_raw.each { |sku, units| (parts[sku] || [ [ sku, 1.0 ] ]).each { |s, q| sold[s] += units.to_f * q } }
      @listings = listings_by_sku(skus, parts)
      asks = @account.ml_full_replenishments.where(seller_sku: skus, recommendation_type: "REPLENISH").group(:seller_sku).sum(:suggested_quantity)
      thumbs = thumbnails(skus)
      rows = products.map do |p|
        olist = p.stock_available.to_f
        info = full.key?(p.sku) ? full[p.sku] : nil
        full_units = info ? info[:available] : 0
        cost = (p.fifo_unit_cost.presence || p.cost_price).to_f
        daily = sold[p.sku].to_f / 30.0
        total = olist + full_units
        coverage = daily.positive? ? (total / daily).round : nil
        { sku: p.sku, description: p.description, thumbnail: thumbs[p.sku], status: p.status,
          olist: olist, reserved: p.stock_reserved.to_f, full: info ? full_units : nil, full_unavailable: info && info[:not_available],
          total: total, unit_cost: cost.positive? ? cost.round(2) : nil, value_olist: (olist * cost).round(2), value_full: (full_units * cost).round(2),
          sold_30d: sold[p.sku].round, coverage_days: coverage, full_asks: asks[p.sku],
          state: state_for(total, coverage, sold[p.sku].round), listings: @listings[p.sku] || [] }
      end
      filtered = filter_depot(rows)
      sorted = sort_depot(filtered)
      page, per = paging
      {
        summary: { skus: rows.size, units_olist: rows.sum { |r| r[:olist] }.round, value_olist: rows.sum { |r| r[:value_olist] }.round(2),
                   units_full: rows.sum { |r| r[:full].to_i }, value_full: rows.sum { |r| r[:value_full] }.round(2),
                   out_of_stock: rows.count { |r| r[:state] == "sem_estoque" }, low: rows.count { |r| r[:state] == "baixo" },
                   stalled: rows.count { |r| r[:state] == "parado" }, without_cost: rows.count { |r| r[:unit_cost].nil? && r[:olist].positive? } },
        rows: sorted.slice((page - 1) * per, per) || [], total: sorted.size, page: page, per_page: per,
        sort: depot_sort_key, low_coverage_days: LOW_COVERAGE_DAYS,
        synced_at: @company.olist_products.maximum(:synced_at)
      }
    end

    # --- aba Full ---

    def full
      recs = @account.ml_full_replenishments.to_a
      items = @account.ml_items.where(user_product_id: recs.map(&:user_product_id)).where(catalog_listing: [ false, nil ])
                      .order(status: :asc).pluck(:user_product_id, :item_id, :title, :thumbnail, :price, :status)
                      .each_with_object({}) { |(up, id, title, thumb, price, status), h| h[up] ||= { item_id: id, title: title, thumbnail: thumb, price: price&.to_f, status: status } }
      found = @company.olist_products.where(sku: recs.map(&:seller_sku).compact, hidden_at: nil).where.not(status: "E").to_a
      # kit: o disponível é quantos kits os componentes permitem montar (Olist::KitResolver)
      kits = Olist::KitResolver.for_kits(@company, found.select { |p| p.kind == "K" })
      olist = found.to_h do |p|
        qty = p.kind == "K" ? kits[p.olist_id]&.available : p.stock_available
        [ p.sku, { available: qty.to_f, description: p.description, kit: p.kind == "K" } ]
      end
      legacy_items = @account.ml_items.where(item_id: recs.map(&:item_id).compact).pluck(:item_id, :title, :thumbnail, :price, :status)
                             .to_h { |id, title, thumb, price, status| [ id, { item_id: id, title: title, thumbnail: thumb, price: price&.to_f, status: status } ] }
      rows = recs.map { |r| full_row(r, (r.item_id && legacy_items[r.item_id]) || items[r.user_product_id] || {}, olist[r.seller_sku]) }
      filtered = filter_full(rows)
      sorted = sort_full(filtered)
      page, per = paging
      reps = rows.select { |r| r[:replenish] }
      {
        summary: { products: rows.size, replenish: reps.size, urgent: rows.count { |r| r[:urgency] == "URGENT" },
                   suggested_units: reps.sum { |r| r[:suggested].to_i }, can_send_units: reps.sum { |r| r[:can_send].to_i },
                   to_buy_units: reps.sum { |r| r[:to_buy].to_i }, out_of_stock: rows.count { |r| r[:in_full] && r[:stock].to_i.zero? },
                   lost_revenue: rows.sum { |r| r[:lost_revenue].to_f }.round(2) },
        rows: sorted.slice((page - 1) * per, per) || [], total: sorted.size, page: page, per_page: per,
        sort: full_sort_key, dir: full_sort_key && full_sort_dir,
        synced_at: @account.full_replenishment_synced_at
      }
    end

    private

    def full_row(r, item, olist)
      history = Array(r.sales_history)
      units = history.sum { |h| h["units_sold"].to_i }
      days_out = history.sum { |h| h["days_out_of_stock"].to_i }
      days_with = history.size * 7 - days_out
      daily = days_with.positive? ? units.to_f / days_with : 0.0
      lost_units = (daily * days_out).round(1)
      price = item[:price] || (r.units_30d.to_i.positive? ? r.gmv_30d.to_f / r.units_30d : nil)
      available = olist && olist[:available]
      suggested = r.replenish? ? r.suggested_quantity.to_i : nil
      can_send = suggested && available ? [ suggested, [ available.floor, 0 ].max ].min : (suggested ? 0 : nil)
      {
        user_product_id: r.user_product_id, inventory_id: r.inventory_id, sku: r.seller_sku,
        title: item[:title] || olist&.dig(:description), thumbnail: item[:thumbnail], item_id: item[:item_id], price: price&.round(2),
        legacy: r.source == "legacy", variation_label: r.variation_label,
        coverage_days: r.units_30d.to_i.positive? && r.total_stock ? (r.total_stock.to_f / (r.units_30d / 30.0)).round : nil,
        in_full: r.inventory_id.present?, restricted: Array(r.tags).include?("is_restricted"), star: Array(r.tags).include?("star_product"),
        stock: r.total_stock, urgency: r.shipping_urgency, urgency_label: MlFullReplenishment::URGENCY_LABELS[r.shipping_urgency] || r.shipping_urgency,
        replenish: r.replenish?, suggested: suggested, deadline: r.replenishment_deadline,
        deadline_label: MlFullReplenishment::DEADLINE_LABELS[r.replenishment_deadline] || r.replenishment_deadline&.downcase&.tr("_", " "),
        frequency: r.replenishment_frequency, units_30d: r.units_30d, gmv_30d: r.gmv_30d&.to_f,
        history: history, days_out: days_out, lost_units: lost_units, lost_revenue: price ? (lost_units * price).round(2) : nil,
        olist_available: available, can_send: can_send, to_buy: suggested && can_send ? suggested - can_send : nil,
        benefits: r.benefits, synced_at: r.synced_at
      }
    end

    # Colunas da tabela do Full que dá para ordenar (pedido do usuário em 24/11/2026), com `sort` e `dir` (asc|desc, padrão
    # desc). Urgência: maior = mais urgente. Sem `sort` vale a ordem padrão: repor primeiro, por urgência, sugerido e receita
    # perdida; ela também desempata as colunas.
    FULL_SORTS = {
      "title" => ->(r) { r[:title].to_s.downcase.presence },
      "stock" => ->(r) { r[:stock] },
      "urgency" => ->(r) { (i = MlFullReplenishment::URGENCY_ORDER.index(r[:urgency])) && MlFullReplenishment::URGENCY_ORDER.size - i },
      "suggested" => ->(r) { r[:suggested] },
      "olist" => ->(r) { r[:olist_available] },
      "can_send" => ->(r) { r[:can_send] },
      "to_buy" => ->(r) { r[:to_buy] },
      "sold" => ->(r) { r[:units_30d] }
    }.freeze

    def full_sort_key = FULL_SORTS.key?(@params[:sort].to_s) ? @params[:sort].to_s : nil
    def full_sort_dir = @params[:dir].to_s == "asc" ? "asc" : "desc"

    def default_full_order(r)
      [ r[:replenish] ? 0 : 1, MlFullReplenishment::URGENCY_ORDER.index(r[:urgency]) || 9, -(r[:suggested] || 0), -(r[:lost_revenue] || 0) ]
    end

    # Linhas sem valor na coluna (ex.: sem sugestão, SKU fora do Olist) ficam sempre no fim, nas duas direções.
    def sort_full(rows)
      base = rows.sort_by { |r| default_full_order(r) }
      return base unless (key = full_sort_key)

      sign = full_sort_dir == "asc" ? 1 : -1
      ranked = base.each_with_index.map { |r, i| [ FULL_SORTS[key].call(r), i, r ] }
      with, without = ranked.partition { |v, _, _| !v.nil? }
      with.sort { |(va, ia, _), (vb, ib, _)| ((va <=> vb) * sign).nonzero? || (ia <=> ib) }.map(&:last) + without.map(&:last)
    end

    def filter_full(rows)
      q = @params[:q].to_s.strip.downcase.presence
      rows = rows.select { |r| [ r[:sku], r[:title], r[:item_id], r[:variation_label] ].compact.any? { |v| v.downcase.include?(q) } } if q
      case @params[:view].to_s
      when "repor" then rows.select { |r| r[:replenish] }
      when "urgente" then rows.select { |r| r[:urgency] == "URGENT" }
      when "falta_comprar" then rows.select { |r| r[:to_buy].to_i.positive? }
      when "sem_necessidade" then rows.reject { |r| r[:replenish] }
      when "todos" then rows
      else rows.select { |r| r[:in_full] }
      end
    end

    def state_for(total, coverage, sold)
      return "sem_estoque" if total <= 0
      return "parado" if sold.zero?
      return "baixo" if coverage && coverage < LOW_COVERAGE_DAYS

      "ok"
    end

    # Busca (pedido do usuário em 14/11/2026): SKU, número do anúncio (MLB), título do anúncio ou palavra do nome do produto.
    # Anúncio de kit também acha os componentes. Várias palavras: todas precisam aparecer.
    def filter_depot(rows)
      q = I18n.transliterate(@params[:q].to_s).downcase.squish.presence
      if q
        words = q.split
        rows = rows.select do |r|
          text = I18n.transliterate([ r[:sku], r[:description], *r[:listings].flat_map { |l| [ l[:item_id], l[:title], l[:sku] ] } ].compact.join(" ")).downcase
          words.all? { |w| text.include?(w) }
        end
      end
      case @params[:view].to_s
      when "sem_estoque", "baixo", "parado", "ok" then rows.select { |r| r[:state] == @params[:view].to_s }
      when "com_estoque" then rows.select { |r| r[:olist].positive? }
      when "pedido_full" then rows.select { |r| r[:full_asks].to_i.positive? }
      else rows
      end
    end

    DEPOT_SORTS = %w[value coverage sold olist sku].freeze
    def depot_sort_key = DEPOT_SORTS.include?(@params[:sort].to_s) ? @params[:sort].to_s : "value"

    def sort_depot(rows)
      case depot_sort_key
      when "coverage" then rows.sort_by { |r| [ r[:coverage_days].nil? ? 1 : 0, r[:coverage_days] || 0 ] }
      when "sold" then rows.sort_by { |r| -r[:sold_30d] }
      when "olist" then rows.sort_by { |r| -r[:olist] }
      when "sku" then rows.sort_by { |r| r[:sku].to_s }
      else rows.sort_by { |r| -(r[:value_olist] + r[:value_full]) }
      end
    end

    def paging
      per = @params[:per_page].to_i.positive? ? @params[:per_page].to_i.clamp(10, 200) : PER_PAGE
      [ [ @params[:page].to_i, 1 ].max, per ]
    end

    # Unidades vendidas nos últimos 30 dias em todas as contas da empresa, pelo SKU da venda.
    def units_sold(skus)
      MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
                 .where(o: { ml_account_id: @company.ml_accounts.select(:id) }).where.not(o: { status: %w[cancelled invalid] })
                 .where("o.date_created >= ?", 30.days.ago).where(sku: skus).group(:sku).sum(:quantity)
    end

    # SKU => anúncios do ML (todas as contas) com esse SKU ou com um kit que o contém: [{ item_id, title, sku, kit }].
    def listings_by_sku(skus, parts)
      kit_of = Hash.new { |h, k| h[k] = [] }
      parts.each { |kit, comps| comps.each { |s, _| kit_of[s] << kit } }
      # SKU de cada anúncio: o do anúncio, os das variações e os vendidos nele (o anúncio do kit costuma ter outro SKU)
      accounts = @company.ml_accounts.select(:id)
      titles = {}
      items = Hash.new { |h, k| h[k] = [] }
      MlItem.where(ml_account_id: accounts).pluck(:item_id, :title, :sku, :inventory_refs).each do |id, title, sku, refs|
        titles[id] = title
        ([ sku ] + Array(refs).map { |r| r["sku"] }).compact_blank.uniq.each { |k| items[k] << id }
      end
      MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id").where(o: { ml_account_id: accounts })
                 .where("o.date_created >= ?", 95.days.ago).distinct.pluck(:item_id, :sku).each { |id, k| items[k] << id if k.present? }
      entry = ->(id, sku, kit) { { item_id: id, title: titles[id], sku: sku, kit: kit } }
      skus.to_h do |s|
        own = items[s].uniq.map { |id| entry.(id, s, false) }
        via = kit_of[s].flat_map { |k| items[k].uniq.map { |id| entry.(id, k, true) } }
        [ s, (own + via).uniq { |l| l[:item_id] } ]
      end
    end

    def thumbnails(skus)
      MlItem.where(ml_account_id: @company.ml_accounts.select(:id), sku: skus).where.not(thumbnail: nil)
            .order(Arel.sql("CASE WHEN status = 'active' THEN 0 ELSE 1 END")).pluck(:sku, :thumbnail)
            .each_with_object({}) { |(s, t), h| h[s] ||= t }
    end
  end
end
