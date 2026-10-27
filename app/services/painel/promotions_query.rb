# Seção Promoções: anúncios ativos com a promoção atual, a melhor oferta disponível (maior margem dentro da faixa
# mínima–máxima) e o ganho da troca; promoções da Central do ML; detalhe de um anúncio com todas as ofertas;
# exportação em CSV. Margem mínima: a do anúncio (ml_promotion_settings) ou a geral da empresa (min_margin_pct).
require "csv" # stdlib; vira gem no Ruby 3.4

module Painel
  class PromotionsQuery
    PER_PAGES = [ 25, 50, 100 ].freeze
    SORTS = %w[gain margin best_margin title price].freeze
    STATUSES = {
      "trocar" => [ "Trocar por melhor", "warn" ], "sem_promocao" => [ "Sem promoção", "warn" ],
      "ok" => [ "Na melhor", "ok" ], "abaixo_minima" => [ "Abaixo da mínima", "bad" ],
      "sem_oferta" => [ "Sem oferta na margem", "neutral" ], "sem_custo" => [ "Sem custo", "neutral" ]
    }.freeze
    GAIN_EPSILON = 0.01

    def self.call(account, params) = new(account, params).call
    def self.detail(account, item_id) = new(account, {}).detail(item_id)
    def self.export_csv(account) = new(account, {}).export_csv
    def self.evaluate_item(account, item_id) = new(account, {}).evaluate_item(item_id)
    def self.actions(account, params) = new(account, params).actions

    KIND_LABELS = { "aderir" => "Entrou", "ajustar_preco" => "Ajustou o preço", "trocar" => "Trocou", "sair" => "Saiu" }.freeze
    SOURCE_LABELS = { "tela" => "Pela tela", "lote" => "Em lote", "rotina" => "Rotina das 03:00", "simulacao" => "Simulação" }.freeze

    def initialize(account, params)
      @account = account
      @company = account.company
      @params = params
    end

    def call
      rows = build_rows(items_scope.to_a)
      counts = STATUSES.keys.index_with { |k| rows.count { |r| r[:status][:key] == k } }
      filtered = filter(rows)
      sorted = sort(filtered)
      page, per = paging

      {
        summary: summary(rows), counts: counts,
        items: sorted.slice((page - 1) * per, per) || [],
        total: sorted.size, page: page, per_page: per, sort: sort_key, dir: sort_dir,
        promotions: promotions,
        rules: { min_margin_pct: @company.min_margin_pct.to_f, max_margin_pct: @company.max_margin_pct&.to_f },
        synced_at: @account.promotions_synced_at
      }
    end

    def detail(item_id)
      item = @account.ml_items.find(item_id)
      row, evaluated = build_row(item, offers_by_item([ item.item_id ])[item.item_id] || [], context([ item ]), with_offers: true)
      row.merge(offers: evaluated.sort_by { |e| [ e[:valid] ? 0 : 1, -(e[:margin_pct] || -999) ] }.map { |e| offer_payload(e) },
                sku_items: sku_siblings(item))
    end

    # => { item:, row:, current:, best:, evaluated: } de um anúncio (usado para aplicar a melhor oferta).
    def evaluate_item(item_id)
      item = @account.ml_items.find(item_id)
      row, evaluated = build_row(item, offers_by_item([ item.item_id ])[item.item_id] || [], context([ item ]))
      { item: item, row: row, evaluated: evaluated, current: @last_current, best: @last_best }
    end

    # Histórico das ações nas promoções, as mais novas primeiro (filtro opcional por anúncio).
    def actions
      scope = @account.ml_promotion_actions.order(created_at: :desc).limit(200)
      scope = scope.where(item_id: @params[:item_id]) if @params[:item_id].present?
      titles = @account.ml_items.where(item_id: scope.map(&:item_id).uniq).pluck(:item_id, :title).to_h
      users = User.where(id: scope.map(&:user_id).compact.uniq).pluck(:id, :name).to_h
      scope.map do |a|
        { id: a.id, item_id: a.item_id, title: titles[a.item_id], kind: a.kind, kind_label: KIND_LABELS.fetch(a.kind, a.kind),
          source: a.source, source_label: SOURCE_LABELS.fetch(a.source, a.source), ok: a.ok, error: a.error,
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
                :available_quantity, :ship_cost, :fee_now, :fee_details, :category_id)
    end

    def offers_by_item(item_ids)
      @account.ml_promotion_offers.where(item_id: item_ids).to_a.group_by(&:item_id)
    end

    def context(items)
      skus = items.map(&:sku).compact_blank.uniq
      {
        olist: Olist::UnitCost.for_skus(@company, skus),
        manual: @company.ml_costs.where(sku: skus).index_by(&:sku),
        settings: @account.ml_promotion_settings.where(item_id: items.map(&:item_id)).index_by(&:item_id)
      }
    end

    def build_rows(items)
      by_item = offers_by_item(items.map(&:item_id))
      ctx = context(items)
      items.map { |item| build_row(item, by_item[item.item_id] || [], ctx).first }
    end

    def evaluator_for(item, ctx)
      setting = ctx[:settings][item.item_id]
      rules = PromotionEvaluator::Rules.new(
        min_pct: (setting&.min_margin_pct || @company.min_margin_pct)&.to_f, max_pct: (setting&.max_margin_pct || @company.max_margin_pct)&.to_f,
        tax_pct: @company.tax_pct.to_f, fixed_pct: @company.fixed_expenses_pct.to_f
      )
      PromotionEvaluator.new(item: item, cost: unit_cost(item, ctx), rules: rules)
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
      current = evaluated.select { |e| e[:as_is] && PromotionEvaluator::PRICE_TYPES.include?(e[:offer].promotion_type) }
        .max_by { |e| e[:offer].status == "started" ? 1 : 0 }
      best = evaluator.best(evaluated)
      @last_current = current
      @last_best = best
      full_price = (item.original_price || item.price).to_f
      setting = ctx[:settings][item.item_id]
      cost = unit_cost(item, ctx)

      row = {
        item_id: item.item_id, title: item.title, sku: item.sku, thumbnail: item.thumbnail, permalink: item.permalink,
        listing_type: item.listing_type_id, logistic_type: item.logistic_type, stock: item.available_quantity,
        full_price: full_price, cost: cost,
        base: evaluator.base(full_price)&.slice(:price, :profit, :margin_pct),
        current: current && short(current), best: best && short(best),
        gain: gain(current, best),
        offers_count: evaluated.count { |e| e[:valid] },
        settings: {
          min_margin_pct: setting&.min_margin_pct&.to_f, max_margin_pct: setting&.max_margin_pct&.to_f,
          apply_to_sku: setting&.apply_to_sku || false, automation_enabled: setting.nil? || setting.automation_enabled,
          effective_min_pct: (setting&.min_margin_pct || @company.min_margin_pct).to_f,
          effective_max_pct: (setting&.max_margin_pct || @company.max_margin_pct)&.to_f
        },
        status: status_label(status_key(cost, current, best))
      }
      [ row, evaluated ]
    end

    def status_key(cost, current, best)
      return "sem_custo" if cost.nil?
      return (current && !current[:valid] ? "abaixo_minima" : "sem_oferta") if best.nil? && (current.nil? || !current[:valid])
      return "sem_promocao" if current.nil?
      return "abaixo_minima" unless current[:valid]
      return "trocar" if best && !best.equal?(current) && best[:profit] - current[:profit] > GAIN_EPSILON

      "ok"
    end

    def gain(current, best)
      return nil if best.nil? || current.nil? || best.equal?(current)

      (best[:profit] - current[:profit]).round(2)
    end

    def short(e)
      o = e[:offer]
      { promotion_id: o.promotion_id, type: o.promotion_type, label: e[:label], name: o.name, status: o.status,
        price: e[:price], margin_pct: e[:margin_pct], profit: e[:profit], meli_amount: e[:meli_amount],
        valid: e[:valid], reason: e[:reason], finish_date: o.finish_date,
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
                     fee: e[:fee], flexible: o.flexible?, start_date: o.start_date)
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

    # --- filtros, ordenação e paginação ---

    def filter(rows)
      rows = rows.select { |r| r[:status][:key] == @params[:status].to_s } if STATUSES.key?(@params[:status].to_s)
      if (promo = @params[:promotion_id].presence)
        ids = @account.ml_promotion_offers.where(promotion_id: promo).pluck(:item_id).to_set
        rows = rows.select { |r| ids.include?(r[:item_id]) }
      end
      if (q = @params[:q].to_s.strip.downcase).present?
        rows = rows.select { |r| [ r[:item_id], r[:sku], r[:title] ].compact.any? { |v| v.downcase.include?(q) } }
      end
      rows
    end

    def sort_key = SORTS.include?(@params[:sort].to_s) ? @params[:sort].to_s : "gain"
    def sort_dir = @params[:dir].to_s == "asc" ? "asc" : "desc"

    def sort(rows)
      rows.sort_by do |r|
        value = case sort_key
        when "gain" then r[:gain]
        when "margin" then r.dig(:current, :margin_pct)
        when "best_margin" then r.dig(:best, :margin_pct)
        when "price" then r[:full_price]
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
