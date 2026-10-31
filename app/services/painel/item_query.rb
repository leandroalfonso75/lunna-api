# Filtro, busca, ordenação, paginação e contagens da tabela completa de
# anúncios (SPEC 7.7, contrato exato em 10.4). Roda em cima de item_metrics
# (recalculada a cada sync) pra filtro numérico e ordenação virarem SQL com
# índice; ml_items só entra pro fim, e só pros campos que item_metrics não
# guarda (quality_level, quality_pending) — e só das linhas da página.
module Painel
  class ItemQuery
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200
    DEFAULT_SORT = :units_7d

    NUMERIC_FILTERS = %i[price stock visits_7d units_7d conversion_7d units_delta revenue_7d coverage_days quality_score].freeze
    # Ordenações calculadas em Ruby (não são colunas de item_metrics): o lucro depende do custo do Olist, das
    # tarifas e dos parâmetros da empresa, então tudo é ordenado antes de montar a página.
    COMPUTED_SORTS = %i[net_profit_pct net_profit_after_ads_pct].freeze
    SORTABLE_COLUMNS = (NUMERIC_FILTERS + %i[title status sku] + COMPUTED_SORTS).freeze
    ASC_DEFAULT_COLUMNS = %i[title status sku coverage_days].freeze

    # "Finalizados/inativos sem faturamento nos últimos 60 dias" (SPEC 6):
    # payload enxuto, sem under_review (esse ainda precisa de atenção).
    LEAN_STATUSES = %w[closed inactive].freeze
    LEAN_KEEP = %i[id title status status_label sku price stock listing_type_label full links lean].freeze

    def self.call(account, params) = new(account, params).call

    def initialize(account, params)
      @account = account
      @params = params
      @invalid_filters = []
    end

    def call
      base = @account.item_metrics
      counts = status_counts(base)

      relation = @params[:id].present? ? base.where(item_id: @params[:id]) : filtered_relation(base)
      total = relation.count

      sort_column, dir = resolve_sort
      page = resolve_page
      per_page = resolve_per_page

      page_metrics, economics = page_of(relation, sort_column, dir, page, per_page)

      {
        items: build_items(page_metrics, economics),
        total: total, page: page, per_page: per_page,
        status_counts: counts,
        active_filter: { alert: active_alert_info },
        active_filters_count: active_filters_count,
        invalid_filters: @invalid_filters,
        sort: sort_column, dir: dir
      }
    end

    private

    # [metrics da página, economics já calculada ou nil]. Ordenação em SQL, ou em Ruby quando a coluna é calculada.
    def page_of(relation, sort_column, dir, page, per_page)
      return sorted_by_economics(relation, sort_column, dir, page, per_page) if COMPUTED_SORTS.include?(sort_column)

      [ relation.order(order_clause(sort_column, dir)).offset((page - 1) * per_page).limit(per_page).to_a, nil ]
    end

    def sorted_by_economics(relation, column, dir, page, per_page)
      metrics = relation.to_a
      economics = Painel::ItemEconomics.for_page(@account, metrics)
      ranked = metrics.sort_by { |metric| economics_sort_key(metric, economics[metric.item_id], column, dir) }

      [ ranked.slice((page - 1) * per_page, per_page) || [], economics ]
    end

    # Sem lucro calculado (sem custo ou sem preço) vai sempre para o fim; desempate por visitas e id, como no SQL.
    def economics_sort_key(metric, economics, column, dir)
      tie = [ -metric.visits_7d.to_i, metric.item_id ]
      value = economics&.dig(column)
      return [ 1, 0, *tie ] if value.nil?

      [ 0, dir == "desc" ? -value : value, *tie ]
    end

    # ---- escopo (status/alert/id) ----

    def filtered_relation(base)
      relation = @params[:alert].present? ? alert_scope(base) : status_scope(base)
      relation = apply_search(relation)
      relation = apply_type(relation)
      relation = apply_shipping(relation)
      apply_column_filters(relation)
    end

    def alert_scope(base)
      Painel::Alerts.scope_for(@params[:alert], base) || status_scope(base)
    end

    def status_scope(relation)
      case @params[:status]
      when "paused" then relation.where(status: "paused")
      when "closed" then relation.where(status: LEAN_STATUSES + [ "under_review" ])
      when "all" then relation
      else relation.where(status: "active")
      end
    end

    def status_counts(base)
      counts = base.group(:status).count
      {
        active: counts["active"].to_i,
        paused: counts["paused"].to_i,
        closed: LEAN_STATUSES.sum { |status| counts[status].to_i } + counts["under_review"].to_i,
        all: counts.values.sum
      }
    end

    def active_alert_info
      rule = @params[:alert].present? && Painel::Alerts::RULES.find { |r| r.key == @params[:alert] }
      rule ? { key: rule.key, title: rule.title } : nil
    end

    # ---- busca e selects ----

    def apply_search(relation)
      return relation if @params[:q].blank?

      term = like_term(@params[:q])
      relation.where("title ILIKE :term OR item_id ILIKE :term OR sku ILIKE :term", term: term)
    end

    def apply_type(relation)
      %w[P C].include?(@params[:type]) ? relation.where(listing_type: @params[:type]) : relation
    end

    def apply_shipping(relation)
      case @params[:shipping]
      when "full" then relation.where(full: true)
      when "non_full" then relation.where(full: false)
      else relation
      end
    end

    # ---- filtros de coluna (f[...]) ----

    def apply_column_filters(relation)
      f = @params[:f]
      return relation unless f

      relation = apply_title_filter(relation, f[:title])
      relation = apply_sku_filter(relation, f[:sku])

      NUMERIC_FILTERS.reduce(relation) { |rel, column| apply_numeric_filter(rel, column, f[column]) }
    end

    def apply_title_filter(relation, raw)
      return relation if raw.blank?

      term = like_term(raw)
      relation.where("title ILIKE :term OR item_id ILIKE :term", term: term)
    end

    def apply_sku_filter(relation, raw)
      return relation if raw.blank?

      raw.strip.casecmp("sem sku").zero? ? relation.where(sku: [ nil, "" ]) : relation.where("sku ILIKE ?", like_term(raw))
    end

    def apply_numeric_filter(relation, column, raw)
      return relation if raw.blank?

      parsed = Painel::FilterExpression.parse(raw)
      return relation if parsed.nil?

      if parsed == :invalid
        @invalid_filters << column.to_s
        return relation
      end

      Painel::FilterExpression.apply(relation, column, parsed)
    end

    def like_term(raw) = "%#{ActiveRecord::Base.sanitize_sql_like(raw)}%"

    # ---- ordenação e paginação ----

    def resolve_sort
      column = @params[:sort].to_s.to_sym
      column = DEFAULT_SORT unless SORTABLE_COLUMNS.include?(column)

      dir = @params[:dir].to_s
      dir = ASC_DEFAULT_COLUMNS.include?(column) ? "asc" : "desc" unless %w[asc desc].include?(dir)

      [ column, dir ]
    end

    # Nulos sempre no fim (nas duas direções); desempate por visits_7d
    # decrescente, depois item_id (SPEC 10.4).
    def order_clause(column, dir)
      Arel.sql("#{column} #{dir.upcase} NULLS LAST, visits_7d DESC, item_id ASC")
    end

    def resolve_page
      page = @params[:page].to_i
      page < 1 ? 1 : page
    end

    def resolve_per_page
      per_page = @params[:per_page].presence&.to_i || DEFAULT_PER_PAGE
      per_page = DEFAULT_PER_PAGE if per_page < 1
      [ per_page, MAX_PER_PAGE ].min
    end

    def active_filters_count
      count = [ @params[:q], @params[:type], @params[:shipping], @params[:alert] ].count(&:present?)
      f = @params[:f]
      return count unless f

      count + [ f[:title], f[:sku], *NUMERIC_FILTERS.map { |column| f[column] } ].count(&:present?)
    end

    # ---- montagem das linhas ----

    def build_items(metrics, economics = nil)
      return [] if metrics.empty?

      ids = metrics.map(&:item_id)
      details = @account.ml_items.where(item_id: ids).pluck(:item_id, :quality_level, :quality_pending)
        .to_h { |item_id, level, pending| [ item_id, [ level, pending ] ] }
      alert_keys = Painel::Alerts.keys_by_item(@account.item_metrics.where(item_id: ids))
      economics ||= Painel::ItemEconomics.for_page(@account, metrics)

      metrics.map { |metric| build_item(metric, details[metric.item_id], alert_keys[metric.item_id] || [], economics[metric.item_id]) }
    end

    def build_item(metric, details, alert_keys, economics)
      quality_level, quality_pending = details || [ nil, [] ]
      price = metric.price
      original_price = metric.original_price

      row = {
        id: metric.item_id, title: metric.title, status: metric.status,
        status_label: Painel::Labels.status(metric.status), sku: metric.sku,
        price: price&.to_f, original_price: original_price&.to_f,
        discount_pct: discount_pct(price, original_price),
        listing_type_label: Painel::Labels.listing_type(metric.listing_type),
        full: metric.full, free_shipping: metric.free_shipping, catalog: metric.catalog,
        variations: metric.variations, stock: metric.stock, stock_state: stock_state(metric),
        visits_7d: metric.visits_7d, prev_visits_7d: metric.prev_visits_7d,
        units_7d: metric.units_7d, prev_units_7d: metric.prev_units_7d, units_today: metric.units_today,
        conversion_7d: metric.conversion_7d&.to_f, prev_conversion_7d: metric.prev_conversion_7d&.to_f,
        units_delta: metric.units_delta, units_delta_direction: units_delta_direction(metric.units_delta),
        revenue_7d: metric.revenue_7d.to_f, net_after_fee_7d: metric.net_after_fee_7d.to_f,
        economics: economics,
        coverage_days: metric.coverage_days&.to_f, coverage_state: coverage_state(metric.coverage_days),
        quality_score: metric.quality_score, quality_state: quality_state(metric.quality_score),
        quality_level: quality_level, quality_actions: quality_actions(quality_pending),
        alert_keys: alert_keys, links: Painel::Labels.links(metric.item_id), lean: false
      }

      lean?(metric) ? leanify(row) : row
    end

    def discount_pct(price, original_price)
      return nil unless original_price.present? && price.present? && original_price > price

      ((1 - price / original_price) * 100).round
    end

    def stock_state(metric) = metric.status == "active" && metric.stock.to_i.zero? ? "bad" : "ok"

    def coverage_state(coverage_days)
      return nil if coverage_days.nil?

      coverage_days < 14 ? "bad" : "ok"
    end

    def quality_state(score)
      return nil if score.nil?
      return "ok" if score >= 80
      return "warn" if score >= 60

      "bad"
    end

    def units_delta_direction(delta)
      return nil if delta.nil?
      return "flat" if delta.zero?

      delta.positive? ? "up" : "down"
    end

    def quality_actions(pending)
      Array(pending).first(6).map { |entry| { title: entry["title"], label: entry["label"] } }
    end

    def lean?(metric)
      LEAN_STATUSES.include?(metric.status) && (metric.revenue_30d.to_f + metric.prev_revenue_30d.to_f) <= 0
    end

    def leanify(row)
      row.each_key { |key| row[key] = nil unless LEAN_KEEP.include?(key) }
      row.merge!(quality_actions: [], alert_keys: [], lean: true)
    end
  end
end
