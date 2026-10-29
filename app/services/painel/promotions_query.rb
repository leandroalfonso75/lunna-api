# Seção Promoções: anúncios ativos com a promoção atual, a melhor oferta disponível (maior margem dentro da faixa
# mínima–máxima, pós Ads) e o ganho da troca; promoções da Central do ML; detalhe de um anúncio com todas as ofertas;
# exportação em CSV. Margem mínima: a do anúncio (ml_promotion_settings) ou a geral da empresa (min_margin_pct).
require "csv" # stdlib; vira gem no Ruby 3.4

module Painel
  class PromotionsQuery
    PER_PAGES = [ 25, 50, 100 ].freeze
    SORTS = %w[gain margin best_margin title price].freeze
    STATUSES = {
      "trocar" => [ "Trocar por melhor", "warn" ], "acima_maxima" => [ "Acima da máxima", "warn" ],
      "sem_promocao" => [ "Sem promoção", "warn" ],
      "ok" => [ "Na melhor", "ok" ], "abaixo_minima" => [ "Abaixo da mínima", "bad" ],
      "sem_custo" => [ "Sem custo", "neutral" ], "para_revisar" => [ "Para revisar", "bad" ]
    }.freeze
    GAIN_EPSILON = 0.01
    ADS_DAYS = 15

    def self.call(account, params) = new(account, params).call
    def self.detail(account, item_id) = new(account, {}).detail(item_id)
    def self.export_csv(account) = new(account, {}).export_csv
    def self.evaluate_item(account, item_id) = new(account, {}).evaluate_item(item_id)
    def self.evaluate_all(account) = new(account, {}).evaluate_all
    def self.actions(account, params) = new(account, params).actions

    KIND_LABELS = { "aderir" => "Entrou", "ajustar_preco" => "Ajustou o preço", "trocar" => "Trocou", "sair" => "Saiu",
                    "agendar" => "Entrou na próxima (começa depois)", "reverter" => "Voltou ao preço anterior" }.freeze
    SOURCE_LABELS = { "tela" => "Pela tela", "lote" => "Em lote", "rotina" => "Rotina das 03:00", "simulacao" => "Simulação",
                      "catalogo" => "Catálogo (volta ao preço)" }.freeze

    def initialize(account, params)
      @account = account
      @company = account.company
      @params = params
    end

    # A lista agrupa as variações de um produto (SKUs com o mesmo produto pai no Olist) numa linha só, com os anúncios
    # dentro; anúncio sem pai fica numa linha própria. Contagens, resumo e filtros são por anúncio; a paginação, por linha.
    def call
      rows = build_rows(items_scope.to_a)
      counts = STATUSES.keys.index_with { |k| rows.count { |r| r[:status][:key] == k } }
      counts["nao_automatizados"] = rows.count { |r| r[:manual] }
      counts["catalogo"] = rows.count { |r| r[:catalog] }
      counts["catalogo_perdendo"] = rows.count { |r| r.dig(:catalog_info, :state) == "perdendo" }
      top = group_rows(rows)
      filtered = filter(top)
      sorted = sort(filtered)
      page, per = paging

      {
        summary: summary(rows), counts: counts,
        items: sorted.slice((page - 1) * per, per) || [],
        total: sorted.size, page: page, per_page: per, sort: sort_key, dir: sort_dir,
        promotions: promotions,
        rules: { min_margin_pct: @company.min_margin_pct.to_f, max_margin_pct: @company.max_margin_pct&.to_f },
        automation: { allow_margin_drop: @company.promo_allow_margin_drop, margin_drop_tolerance: @company.promo_margin_drop_tolerance&.to_f,
                      include_catalog: @company.promo_include_catalog },
        catalog_alerts: catalog_alerts,
        synced_at: @account.promotions_synced_at
      }
    end

    # Anúncios de catálogo que seguiram sem ganhar depois de voltar ao preço anterior: análise manual.
    def catalog_alerts
      checks = @account.ml_catalog_checks.where(status: "analise_manual").order(checked_at: :desc).limit(50)
      titles = @account.ml_items.where(item_id: checks.map(&:item_id)).pluck(:item_id, :title).to_h
      checks.map { |c| { id: c.id, item_id: c.item_id, title: titles[c.item_id], ml_status: c.ml_status, message: c.message, checked_at: c.checked_at } }
    end

    def detail(item_id)
      item = @account.ml_items.find(item_id)
      row, evaluated = build_row(item, offers_by_item([ item.item_id ])[item.item_id] || [], context([ item ]), with_offers: true)
      row.merge(offers: evaluated.sort_by { |e| [ e[:valid] ? 0 : 1, -(e[:margin_pct] || -999) ] }.map { |e| offer_payload(e) },
                sku_items: sku_siblings(item),
                variation_items: PromotionSettings.variation_item_ids(@account, item).then do |ids|
                  @account.ml_items.where(item_id: ids).pluck(:item_id, :title, :sku).map { |id, title, sku| { item_id: id, title: title, sku: sku } }
                end)
    end

    # => { item:, row:, current:, best:, evaluated: } de um anúncio (usado para aplicar a melhor oferta).
    def evaluate_item(item_id)
      item = @account.ml_items.find(item_id)
      row, evaluated = build_row(item, offers_by_item([ item.item_id ])[item.item_id] || [], context([ item ]))
      { item: item, row: row, evaluated: evaluated, current: @last_current, best: @last_best, evaluator: @last_evaluator }
    end

    # => [ { item:, row:, current:, best: } ] de todos os anúncios ativos (usado pela rotina das 03:00).
    def evaluate_all
      items = items_scope.to_a
      ctx = context(items)
      items.map do |item|
        row, evaluated = build_row(item, ctx[:offers][item.item_id] || [], ctx)
        { item: item, row: row, current: @last_current, best: @last_best, setting: ctx[:settings][item.item_id],
          evaluated: evaluated, evaluator: @last_evaluator, catalog_entry: @last_catalog_entry }
      end
    end

    # Histórico das ações nas promoções, as mais novas primeiro (filtro opcional por anúncio).
    def actions
      scope = @account.ml_promotion_actions.order(created_at: :desc).limit(200)
      scope = scope.where(item_id: @params[:item_id]) if @params[:item_id].present?
      titles = @account.ml_items.where(item_id: scope.map(&:item_id).uniq).pluck(:item_id, :title).to_h
      users = User.where(id: scope.map(&:user_id).compact.uniq).pluck(:id, :name).to_h
      scope.map do |a|
        { id: a.id, item_id: a.item_id, title: titles[a.item_id], kind: a.kind, kind_label: KIND_LABELS.fetch(a.kind, a.kind),
          source: a.source, source_label: SOURCE_LABELS.fetch(a.source, a.source), ok: a.ok, error: a.error, forced_reason: a.forced_reason,
          from: a.from_type && { name: a.from_name, price: a.from_price&.to_f, margin_pct: a.from_margin_pct&.to_f },
          to: a.to_type && { name: a.to_name, price: a.to_price&.to_f, margin_pct: a.to_margin_pct&.to_f },
          gain: a.gain&.to_f, user: users[a.user_id], created_at: a.created_at }
      end
    end

    def export_csv
      items = items_scope.to_a
      by_item = offers_by_item(items.map(&:item_id))
      ctx = context(items)
      promos = @account.ml_promotions.index_by(&:promotion_id)

      CSV.generate(col_sep: ";") do |csv|
        csv << [ "Promoção", "ID da promoção", "Tipo", "Situação da promoção", "Início", "Fim", "Anúncio", "Título", "SKU",
                 "Situação no anúncio", "Preço original", "Preço da oferta", "Preço mínimo", "Preço máximo", "Parte do ML (%)",
                 "Parte do vendedor (%)", "Margem (%)", "Lucro por unidade (R$)", "Observação" ]
        items.each do |item|
          evaluator = evaluator_for(item, ctx)
          (by_item[item.item_id] || []).each do |offer|
            e = evaluator.evaluate_offer(offer)
            promo = promos[offer.promotion_id]
            csv << [ offer.name || promo&.name || e[:label], offer.promotion_id, e[:label], promo&.status, date(offer.start_date),
                     date(offer.finish_date), item.item_id, item.title, item.sku, offer.status, num(offer.original_price),
                     num(e[:price] || offer.price), num(offer.min_price), num(offer.max_price), num(offer.meli_percentage),
                     num(offer.seller_percentage), num(e[:margin_pct]), num(e[:profit]), e[:reason] ]
          end
        end
      end
    end

    private

    def items_scope
      @account.ml_items.where(status: "active")
        .select(:item_id, :title, :sku, :thumbnail, :permalink, :price, :original_price, :listing_type_id, :logistic_type,
                :available_quantity, :ship_cost, :fee_now, :fee_details, :category_id, :catalog_listing, :item_relations, :sold_quantity,
                :catalog_status, :catalog_price_to_win, :catalog_winner_price, :catalog_checked_at)
    end

    def offers_by_item(item_ids)
      @account.ml_promotion_offers.where(item_id: item_ids).to_a.group_by(&:item_id)
    end

    def context(items)
      skus = items.map(&:sku).compact_blank.uniq
      {
        olist: Olist::UnitCost.for_skus(@company, skus),
        manual: @company.ml_costs.where(sku: skus).index_by(&:sku),
        settings: @account.ml_promotion_settings.where(item_id: items.map(&:item_id)).index_by(&:item_id),
        ads: ads_per_unit(items.map(&:item_id)),
        offers: offers_by_item(items.map(&:item_id)),
        sales: ItemMetric.where(item_id: items.map(&:item_id)).pluck(:item_id, :units_30d).to_h,
        synced_with_catalog: synced_with_catalog
      }
    end

    CATALOG_STATES = { "winning" => "ganhando", "sharing_first_place" => "compartilhando", "competing" => "perdendo",
                       "listed" => "perdendo" }.freeze

    # Anúncio de catálogo: ganhando ou perdendo a vitrine (lido do ML a cada 30 minutos) e, perdendo, o preço para
    # ganhar e a oferta que chega nele (a que dá mais lucro, de preferência dentro das regras).
    def catalog_info(item, current, evaluated, evaluator)
      @last_catalog_entry = nil
      return nil unless item.catalog_listing

      state = CATALOG_STATES[item.catalog_status] || "sem_dados"
      today = (current&.dig(:price) || item.price).to_f
      info = { state: state, ml_status: item.catalog_status, checked_at: item.catalog_checked_at, price_today: today,
               price_to_win: item.catalog_price_to_win&.to_f, winner_price: item.catalog_winner_price&.to_f }
      return info unless state == "perdendo" && info[:price_to_win]

      target = info[:price_to_win]
      info[:reduce_by] = (today - target).round(2)
      info[:reduce_pct] = today.positive? ? ((today - target) / today * 100).round(1) : nil
      entry = catalog_entry(evaluated, evaluator, target)
      @last_catalog_entry = entry
      info[:suggestion] = entry && short(entry)
      info[:message] = if entry.nil? then "nenhuma oferta chega a #{brl(target)}"
      elsif entry[:valid] then "#{entry[:label]} a #{brl(entry[:price])} cabe nas regras"
      else "#{entry[:label]} a #{brl(entry[:price])} chega ao preço, mas fica #{entry[:reason]}"
      end
      info
    end

    # A oferta que chega ao preço para ganhar: as de faixa no próprio preço alvo (se o ML aceitar), as de preço fixo se
    # já estiverem abaixo dele. Prefere a que cabe nas regras e, entre elas, a de maior lucro.
    def catalog_entry(evaluated, evaluator, target)
      seen = {}
      options = evaluated.filter_map do |e|
        o = e[:offer]
        next unless PromotionEvaluator::PRICE_TYPES.include?(o.promotion_type) && o.status != "pending"
        next if seen[[ o.promotion_id, o.promotion_type ]]

        seen[[ o.promotion_id, o.promotion_type ]] = true
        if o.flexible? && target >= o.min_price.to_f - 0.005 && target <= o.max_price.to_f + 0.005
          evaluator.evaluate_offer(o, price: target)
        elsif !o.flexible? && e[:price] && e[:price] <= target + 0.005
          e
        end
      end
      options.select { |e| e[:profit] }.max_by { |e| [ e[:valid] ? 1 : 0, e[:profit] ] }
    end

    def brl(v) = ActiveSupport::NumberHelper.number_to_currency(v, unit: "R$", separator: ",", delimiter: ".")

    # Anúncios tradicionais ligados a um anúncio de catálogo (item_relations de qualquer um dos dois lados).
    def synced_with_catalog
      @synced_with_catalog ||= @account.ml_items.where("jsonb_array_length(item_relations) > 0").pluck(:item_id, :catalog_listing, :item_relations)
        .flat_map { |id, catalog, rel| catalog ? rel.map { |r| r["id"] } : [ id ] }.to_set
    end

    # Custo de Ads por unidade de cada anúncio nos últimos 15 dias fechados: gasto ÷ unidades vendidas (vendas não
    # canceladas). Sem gasto, ou gasto sem nenhuma venda, fica zero (o gasto sem venda aparece à parte).
    def ads_per_unit(item_ids)
      zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
      last = zone.today - 1
      first = last - (ADS_DAYS - 1)
      spend = MlAdItemDaily.where(ml_account_id: @account.id, item_id: item_ids, date: first..last).group(:item_id).sum(:cost)
      units = MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
        .where(o: { ml_account_id: @account.id }).where.not(o: { status: %w[cancelled invalid] })
        .where(item_id: spend.keys).where("o.date_created BETWEEN ? AND ?", first.in_time_zone(zone).beginning_of_day, last.in_time_zone(zone).end_of_day)
        .group("ml_order_items.item_id").sum("ml_order_items.quantity")
      spend.to_h do |id, cost|
        sold = units[id].to_i
        [ id, { spend: cost.to_f.round(2), units: sold, unit: sold.positive? ? (cost.to_f / sold).round(2) : 0.0, days: ADS_DAYS } ]
      end
    end

    def build_rows(items)
      ctx = context(items)
      items.map { |item| build_row(item, ctx[:offers][item.item_id] || [], ctx).first }
    end

    def evaluator_for(item, ctx)
      setting = ctx[:settings][item.item_id]
      ads = ctx[:ads][item.item_id]&.dig(:unit).to_f
      limits = if setting&.limit_mode == "price"
        { min_pct: nil, max_pct: nil, min_price: setting.min_price&.to_f, max_price: setting.max_price&.to_f }
      else
        { min_pct: (setting&.min_margin_pct || @company.min_margin_pct)&.to_f, max_pct: (setting&.max_margin_pct || @company.max_margin_pct)&.to_f }
      end
      rules = PromotionEvaluator::Rules.new(**limits, tax_pct: @company.tax_pct.to_f, fixed_pct: @company.fixed_expenses_pct.to_f, ads_unit: ads,
                                            price_cap: price_cap(item, ctx), current_price: current_price(item, ctx),
                                            allow_margin_drop: @company.promo_allow_margin_drop,
                                            margin_drop_tol: @company.promo_margin_drop_tolerance&.to_f)
      PromotionEvaluator.new(item: item, cost: unit_cost(item, ctx), rules: rules)
    end

    # Preço cheio do anúncio (o Lunna nunca altera): nenhuma oferta pode passar dele. O preço final da promoção pode
    # subir ou descer em relação ao de hoje, desde que fique abaixo do preço cheio e dentro dos limites.
    def price_cap(item, _ctx)
      (item.original_price || item.price)&.to_f
    end

    # Preço da última promoção (o que o comprador paga hoje): base do limite de aumento. Sem promoção, o preço do anúncio.
    def current_price(item, ctx)
      active = (ctx[:offers]&.dig(item.item_id) || [])
        .select { |o| o.status == "started" && o.price.to_f.positive? && PromotionEvaluator::PRICE_TYPES.include?(o.promotion_type) }
      active.map { |o| o.price.to_f }.min || item.price&.to_f
    end

    def unit_cost(item, ctx)
      olist = ctx[:olist][item.sku]
      return olist.value.to_f if olist

      manual = ctx[:manual][item.sku]
      manual ? manual.cost.to_f + manual.extra.to_f : nil
    end

    def build_row(item, offers, ctx, with_offers: false)
      evaluator = evaluator_for(item, ctx)
      evaluated = evaluator.evaluate(offers)
      current = evaluator.current
      best = evaluator.best(evaluated)
      @last_current = current
      @last_best = best
      @last_evaluator = evaluator
      full_price = (item.original_price || item.price).to_f
      setting = ctx[:settings][item.item_id]
      cost = unit_cost(item, ctx)

      row = {
        item_id: item.item_id, title: item.title, sku: item.sku, thumbnail: item.thumbnail, permalink: item.permalink,
        listing_type: item.listing_type_id, logistic_type: item.logistic_type, stock: item.available_quantity,
        # catálogo: anúncio de catálogo (com ou sem sincronização com um tradicional) ou tradicional sincronizado
        catalog: item.catalog_listing ? (item.item_relations.present? ? "sincronizado" : "sem_sincronizacao") : nil,
        synced_with_catalog: !item.catalog_listing && ctx[:synced_with_catalog].include?(item.item_id),
        sold_total: item.sold_quantity, sold_30d: ctx[:sales][item.item_id] || 0,
        catalog_info: catalog_info(item, current, evaluated, evaluator),
        full_price: full_price, cost: cost,
        base: evaluator.base(full_price)&.slice(:price, :profit, :margin_pct, :costs),
        ads: ctx[:ads][item.item_id] || { spend: 0.0, units: 0, unit: 0.0, days: ADS_DAYS },
        current: current && short(current), best: best && short(best),
        gain: gain(current, best),
        offers_count: evaluated.count { |e| e[:valid] },
        settings: {
          limit_mode: setting&.limit_mode || "margin",
          min_margin_pct: setting&.min_margin_pct&.to_f, max_margin_pct: setting&.max_margin_pct&.to_f,
          min_price: setting&.min_price&.to_f, max_price: setting&.max_price&.to_f,
          apply_to_sku: setting&.apply_to_sku || false, apply_to_variations: setting&.apply_to_variations || false,
          rules_note: setting&.rules_note,
          automation_enabled: setting.nil? || setting.automation_enabled,
          effective_min_pct: (setting&.min_margin_pct || @company.min_margin_pct).to_f,
          effective_max_pct: (setting&.max_margin_pct || @company.max_margin_pct)&.to_f
        },
        status: status_label(status_key(cost, current, best, evaluator)),
        review: review_for(cost, current, best, evaluated, evaluator),
        notes: setting&.rules_note.presence,
        # "não automatizar promoções neste anúncio": a rotina e o lote não mexem; a melhor oferta segue sugerida
        manual: setting.present? && !setting.automation_enabled
      }
      [ row, evaluated ]
    end

    def status_key(cost, current, best, evaluator)
      return "sem_custo" if cost.nil?
      return "para_revisar" if needs_review?(current, best, evaluator)
      return "sem_promocao" if current.nil?
      return "acima_maxima" if current[:reason] == "acima da margem máxima"
      return "abaixo_minima" unless current[:valid]
      return "trocar" if changes?(current, best)

      "ok"
    end

    # Nenhuma oferta cabe nas regras e a situação de hoje também não (promoção atual fora dos limites, ou sem promoção
    # com o preço do anúncio fora deles): nada é aplicado, vai para revisão.
    def needs_review?(current, best, evaluator)
      return false unless best.nil?
      return !current[:valid] if current

      !evaluator.baseline_valid?
    end

    # A melhor oferta muda algo (outra promoção ou outro preço) em relação à atual.
    def changes?(current, best)
      return false if best.nil? || best.equal?(current) || best[:as_is]

      best[:offer].promotion_id != current[:offer].promotion_id || best[:offer].promotion_type != current[:offer].promotion_type ||
        (best[:price].to_f - current[:price].to_f).abs > GAIN_EPSILON
    end

    # Por que nada foi aplicado: a regra que barrou a promoção atual e as que barraram cada oferta (as mais comuns).
    # Por que nada foi aplicado: a regra que barrou a promoção atual, as que barraram cada oferta (as mais comuns), a
    # melhor oferta barrada (a de maior margem entre as que não cabem, com o que faltou) e o que mudar para caber.
    def review_for(cost, current, best, evaluated, evaluator)
      return nil unless cost && needs_review?(current, best, evaluator)

      offers = evaluated.reject { |e| e[:as_is] }.select { |e| e[:reason].present? && PromotionEvaluator::PRICE_TYPES.include?(e[:offer].promotion_type) }
      tally = offers.group_by { |e| e[:reason] }.transform_values(&:size).sort_by { |_, n| -n }
      # melhor barrada: só as que a automação escolheria (sem campanha do vendedor) e que rendem mais que hoje;
      # oferta no mesmo preço e lucro da atual não é sugerida (trocar não muda nada)
      blocked = offers.select { |e| e[:margin_pct] && e[:offer].promotion_type != "SELLER_CAMPAIGN" }
        .select { |e| current.nil? || e[:profit] > current[:profit].to_f + GAIN_EPSILON }
        .max_by { |e| [ e[:margin_pct], e[:offer].finish_date.to_i ] }
      {
        current_reason: current && current[:reason],
        reasons: tally.first(3).map { |reason, n| { reason: reason, offers: n } },
        label: current&.dig(:reason) || tally.first&.first || "nenhuma oferta disponível",
        blocked_best: blocked && short(blocked).merge(shortfall: shortfall(blocked, evaluator.rules)),
        suggestion: blocked && suggestion(blocked, evaluator.rules),
        suggested: blocked && suggested_limit(blocked)
      }
    end

    # Campo e valor que, preenchidos nos limites do anúncio, fariam a melhor barrada caber (botão "Usar a sugestão").
    def suggested_limit(e)
      case e[:reason]
      when "abaixo da margem mínima" then e[:margin_pct].positive? ? { field: "min_margin_pct", value: e[:margin_pct].floor(1) } : nil
      when "acima da margem máxima" then { field: "max_margin_pct", value: e[:margin_pct].ceil(1) }
      when "abaixo do valor mínimo" then { field: "min_price", value: e[:price] }
      when "acima do valor máximo" then { field: "max_price", value: e[:price] }
      end
    end

    # O que faltou para a oferta barrada caber na regra que a barrou.
    def shortfall(e, rules)
      case e[:reason]
      when "abaixo da margem mínima" then format("margem %.1f%%, mínima %.1f%%: faltam %.1f p.p.", e[:margin_pct], rules.min_pct, rules.min_pct - e[:margin_pct])
      when "acima da margem máxima" then format("margem %.1f%%, máxima %.1f%%: %.1f p.p. acima", e[:margin_pct], rules.max_pct, e[:margin_pct] - rules.max_pct)
      when "abaixo do valor mínimo" then format("preço R$ %.2f, mínimo R$ %.2f", e[:price], rules.min_price)
      when "acima do valor máximo" then format("preço R$ %.2f, máximo R$ %.2f", e[:price], rules.max_price)
      else e[:reason]
      end
    end

    # Mudança nos limites do anúncio que faria a melhor oferta barrada caber.
    def suggestion(e, rules)
      case e[:reason]
      when "abaixo da margem mínima"
        if e[:margin_pct] <= 0 then "nenhuma oferta dá lucro: rever o custo do produto ou o preço cheio do anúncio"
        else format("baixar a margem mínima deste anúncio para %.1f%% (ou reduzir o custo)", e[:margin_pct].floor(1))
        end
      when "acima da margem máxima" then format("subir a margem máxima deste anúncio para %.1f%%", e[:margin_pct].ceil(1))
      when "abaixo do valor mínimo" then format("baixar o valor mínimo para R$ %.2f", e[:price])
      when "acima do valor máximo" then format("subir o valor máximo para R$ %.2f", e[:price])
      when /^aumento acima/ then "esperar a próxima promoção (o limite de aumento é sobre a última) ou trocar por uma oferta de preço menor"
      when /^passaria da casa/ then "escolher uma oferta que fique abaixo da casa de cem"
      when "acima do preço cheio do anúncio" then "nenhuma: o preço cheio é o teto"
      else nil
      end
    end

    def gain(current, best)
      return nil if best.nil? || current.nil? || best.equal?(current)

      (best[:profit] - current[:profit]).round(2)
    end

    def short(e)
      o = e[:offer]
      { promotion_id: o.promotion_id, type: o.promotion_type, label: e[:label], name: o.name, status: o.status,
        price: e[:price], margin_pct: e[:margin_pct], profit: e[:profit], meli_amount: e[:meli_amount],
        valid: e[:valid], reason: e[:reason], start_date: o.start_date || promo_dates(o)&.first, finish_date: o.finish_date || promo_dates(o)&.last, costs: e[:costs],
        action: action_for(e) }
    end

    # O que aplicar esta oferta significa: manter, editar o preço da promoção atual ou entrar nela.
    def action_for(e)
      return "manter" if e[:as_is]
      return "editar_preco" if e[:offer].active?

      "aderir"
    end

    def offer_payload(e)
      o = e[:offer]
      short(e).merge(original_price: o.original_price&.to_f, min_price: o.min_price&.to_f, max_price: o.max_price&.to_f,
                     suggested_price: o.suggested_price&.to_f, meli_percentage: o.meli_percentage&.to_f,
                     seller_percentage: o.seller_percentage&.to_f, fixed_amount: o.fixed_amount&.to_f,
                     fee: e[:fee], flexible: o.flexible?, stock_reserved: o.stock_reserved)
    end

    # Validade da campanha quando a oferta do anúncio não traz datas (ex.: "Impulsione suas vendas").
    def promo_dates(offer)
      @promo_dates ||= @account.ml_promotions.pluck(:promotion_id, :start_date, :finish_date).to_h { |id, s, f| [ id, [ s, f ] ] }
      @promo_dates[offer.promotion_id]
    end

    def sku_siblings(item)
      return [] if item.sku.blank?

      @account.ml_items.where(sku: item.sku, status: %w[active paused]).where.not(item_id: item.item_id)
        .pluck(:item_id, :title, :listing_type_id).map { |id, title, type| { item_id: id, title: title, listing_type: type } }
    end

    def status_label(key)
      label, tone = STATUSES.fetch(key)
      { key: key, label: label, tone: tone }
    end

    def summary(rows)
      with_promo = rows.count { |r| r[:current] }
      {
        items: rows.size, with_promotion: with_promo, without_promotion: rows.size - with_promo,
        to_switch: rows.count { |r| r[:status][:key] == "trocar" },
        switch_gain: rows.sum { |r| r[:status][:key] == "trocar" ? r[:gain].to_f : 0.0 }.round(2),
        below_min: rows.count { |r| r[:status][:key] == "abaixo_minima" },
        to_review: rows.count { |r| r[:status][:key] == "para_revisar" },
        without_cost: rows.count { |r| r[:status][:key] == "sem_custo" }
      }
    end

    def promotions
      counts = @account.ml_promotion_offers.where.not(promotion_id: nil).group(:promotion_id, :status).count
      @account.ml_promotions.order(Arel.sql("finish_date ASC NULLS LAST")).map do |p|
        { promotion_id: p.promotion_id, type: p.promotion_type,
          label: PromotionEvaluator::TYPE_LABELS.fetch(p.promotion_type, p.promotion_type), name: p.name,
          status: p.status, start_date: p.start_date, finish_date: p.finish_date, deadline_date: p.deadline_date,
          active_items: counts.sum { |(id, st), n| id == p.promotion_id && %w[started pending].include?(st) ? n : 0 },
          candidate_items: counts.sum { |(id, st), n| id == p.promotion_id && st == "candidate" ? n : 0 } }
      end
    end

    # --- agrupamento por produto (variações) ---

    STATUS_PRIORITY = %w[para_revisar abaixo_minima trocar acima_maxima sem_promocao sem_custo ok].freeze

    def group_rows(rows)
      skus = rows.map { |r| r[:sku] }.compact_blank.uniq
      parent_of = OlistProduct.where(company_id: @company.id, sku: skus).where.not(parent_olist_id: nil).pluck(:sku, :parent_olist_id).to_h
      parents = OlistProduct.where(company_id: @company.id, olist_id: parent_of.values.uniq).index_by(&:olist_id)

      singles, grouped = rows.partition { |r| parent_of[r[:sku]].nil? }
      groups = grouped.group_by { |r| parent_of[r[:sku]] }.map do |parent_id, children|
        parent = parents[parent_id]
        children = children.sort_by { |c| [ c[:sku].to_s, c[:item_id] ] }
        statuses = children.map { |c| c[:status][:key] }
        worst = STATUS_PRIORITY.find { |k| statuses.include?(k) } || "ok"
        {
          group: true, key: "grp-#{parent_id}", parent_olist_id: parent_id,
          title: parent&.description.presence || children.first[:title], sku: parent&.sku, thumbnail: children.first[:thumbnail],
          item_id: children.first[:item_id], # anúncio que representa o grupo nos limites (aplicados a todas as variações)
          count: children.size, variations: children.map { |c| c[:sku] }.uniq.size,
          price_min: children.map { |c| c[:full_price] }.min, price_max: children.map { |c| c[:full_price] }.max,
          gain: children.filter_map { |c| c[:gain] }.max,
          current_margin: children.filter_map { |c| c.dig(:current, :margin_pct) }.min,
          best_margin: children.filter_map { |c| c.dig(:best, :margin_pct) }.max,
          status: status_label(worst), statuses: statuses.tally,
          children: children
        }
      end
      singles + groups
    end

    # --- filtros, ordenação e paginação ---

    # Filtra por anúncio: um grupo fica quando algum anúncio dele passa, e só com esses anúncios dentro.
    def filter(rows)
      manual_only = @params[:status].to_s == "nao_automatizados"
      catalog_only = @params[:status].to_s == "catalogo"
      status = STATUSES.key?(@params[:status].to_s) ? @params[:status].to_s : nil
      promo_ids = @params[:promotion_id].present? ? @account.ml_promotion_offers.where(promotion_id: @params[:promotion_id]).pluck(:item_id).to_set : nil
      q = @params[:q].to_s.strip.downcase.presence
      keep = lambda do |r|
        (!manual_only || r[:manual]) && (!catalog_only || r[:catalog]) &&
          (status.nil? || r[:status][:key] == status) &&
          (promo_ids.nil? || promo_ids.include?(r[:item_id])) &&
          (q.nil? || [ r[:item_id], r[:sku], r[:title] ].compact.any? { |v| v.downcase.include?(q) })
      end

      rows.filter_map do |r|
        next (keep.call(r) ? r : nil) unless r[:group]

        kids = r[:children].select { |c| keep.call(c) }
        kids = r[:children] if kids.empty? && q && [ r[:sku], r[:title] ].compact.any? { |v| v.downcase.include?(q) } && status.nil? && promo_ids.nil? && !manual_only && !catalog_only
        next nil if kids.empty?

        r.merge(children: kids, matched: kids.size)
      end
    end

    def sort_key = SORTS.include?(@params[:sort].to_s) ? @params[:sort].to_s : "gain"
    def sort_dir = @params[:dir].to_s == "asc" ? "asc" : "desc"

    def sort(rows)
      rows.sort_by do |r|
        value = case sort_key
        when "gain" then r[:gain]
        when "margin" then r[:group] ? r[:current_margin] : r.dig(:current, :margin_pct)
        when "best_margin" then r[:group] ? r[:best_margin] : r.dig(:best, :margin_pct)
        when "price" then r[:group] ? r[:price_min] : r[:full_price]
        when "title" then nil
        end
        next [ 0, r[:title].to_s.downcase ] if sort_key == "title"

        [ value.nil? ? 1 : 0, sort_dir == "asc" ? (value || 0) : -(value || 0) ]
      end.then { |list| sort_key == "title" && sort_dir == "desc" ? list.reverse : list }
    end

    def paging
      per = @params[:per_page].to_i
      per = 50 unless PER_PAGES.include?(per)
      [ [ @params[:page].to_i, 1 ].max, per ]
    end

    def num(v) = v.nil? ? nil : format("%.2f", v.to_f).tr(".", ",")
    def date(t) = t&.in_time_zone("America/Sao_Paulo")&.strftime("%d/%m/%Y %H:%M")
  end
end
