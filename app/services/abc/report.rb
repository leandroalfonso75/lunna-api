# SPEC 10.5/10.6 — orquestra Abc::Classifier/Economics/PriceSuggestion/
# SuggestionEngine pra uma conta inteira e devolve os JSONs prontos pro
# Nuxt. Cálculo completo em cache (chave inclui a última rodada de sync e
# `company.updated_at`, pra invalidar quando os parâmetros mudam); o filtro
# por curva em `call` acontece depois do cache.
#
# ponytail: o cache guarda os ActiveRecord de item_metrics/ml_items direto
# (Marshal); achatar em hashes puros reduziria o tamanho se o cache virar
# gargalo.
module Abc
  class Report
    def self.call(account, curve: "all") = new(account).index(curve)
    def self.item(account, item_id) = new(account).show(item_id)
    def self.item_for_prompt(account, item_id) = new(account).prompt_context(item_id)

    def initialize(account)
      @account = account
      @params = Abc::Params.from(account.company)
    end

    def index(curve)
      data = cached
      rows = curve == "all" ? data[:rows] : data[:rows].select { |row| row[:curve] == curve }

      {
        params: data[:params], period: data[:period], has_costs: data[:has_costs],
        details: data[:details], notice: data[:notice],
        summary: data[:summary], groups: data[:groups], rows: rows
      }
    end

    def show(item_id) = detail_payload(fetch_entry(item_id))

    def prompt_context(item_id)
      entry = fetch_entry(item_id)
      [ detail_payload(entry), row_payload(entry), context_payload(entry) ]
    end

    private

    def fetch_entry(item_id)
      cached[:entries].fetch(item_id) { raise ActiveRecord::RecordNotFound }
    end

    def cached
      last_run_id = @account.ml_sync_runs.order(started_at: :desc).limit(1).pick(:id)
      cache_key = [ "abc", @account.id, last_run_id, @account.company.updated_at.to_i, Date.current ]
      Rails.cache.fetch(cache_key) { compute }
    end

    def compute
      metrics = @account.item_metrics.to_a
      items_by_id = @account.ml_items.where(item_id: metrics.map(&:item_id)).index_by(&:item_id)
      costs = @account.company.ml_costs.to_a
      has_costs = costs.present?
      costs_by_sku = costs.index_by(&:sku)

      classification = Abc::Classifier.call(metrics, @params)
      classified_by_id = classification.rows.index_by { |row| row.metric.item_id }

      entries = build_entries(metrics, items_by_id, costs_by_sku, classification, classified_by_id)
      universe_rows = classification.rows.map { |row| row_payload(entries[row.metric.item_id]) }
      details = details_payload(classification, entries)

      {
        params: @params.to_h, period: period_payload, has_costs: has_costs,
        details: details, notice: notice_for(has_costs, details),
        summary: classification.summary, groups: classification.groups,
        rows: universe_rows, entries: entries
      }
    end

    def build_entries(metrics, items_by_id, costs_by_sku, classification, classified_by_id)
      metrics.each_with_object({}) do |metric, memo|
        item = items_by_id[metric.item_id]
        classified = classified_by_id[metric.item_id]
        cost = cost_for(metric, costs_by_sku)

        economics = Abc::Economics.call(metric: metric, item: item, cost: cost, params: @params)
        price = Abc::PriceSuggestion.call(item: item, metric: metric, economics: economics, cost: cost, params: @params)
        ctx = Abc::SuggestionEngine::Context.new(
          item: item, metric: metric, curve: classified&.curve, group: classified&.group,
          price: price, conversion_median: classification.conversion_median, params: @params
        )

        memo[metric.item_id] = {
          metric: metric, item: item,
          curve: classified&.curve, group: classified&.group, rank: classified&.rank,
          share_pct: classified&.share_pct, cum_pct: classified&.cum_pct,
          units_change_pct: classified&.units_change_pct, units_change_state: classified&.units_change_state,
          is_new: classified&.is_new, economics: economics, price: price,
          suggestions: Abc::SuggestionEngine.call(ctx),
          conversion_median: classification.conversion_median
        }
      end
    end

    def cost_for(metric, costs_by_sku)
      return nil if metric.sku.blank?

      record = costs_by_sku[metric.sku]
      record && (record.cost.to_f + record.extra.to_f)
    end

    def period_payload
      today = Time.zone.today
      { month: { from: today - 30, to: today - 1 }, prev_month: { from: today - 60, to: today - 31 } }
    end

    def details_payload(classification, entries)
      total = classification.rows.size
      done = classification.rows.count { |row| entries[row.metric.item_id][:item]&.details_checked_at.present? }
      { done: done, total: total }
    end

    def notice_for(has_costs, details)
      parts = []
      parts << "Custos dos produtos ainda não cadastrados" unless has_costs
      parts << "Detalhes carregados para #{details[:done]} de #{details[:total]} anúncios" if details[:done] < details[:total]
      parts.presence&.join(" · ")
    end

    def row_payload(entry)
      metric = entry[:metric]
      month = entry[:economics].month

      {
        id: metric.item_id, title: metric.title, status_label: Painel::Labels.status(metric.status),
        sku: metric.sku, full: metric.full, curve: entry[:curve], group: entry[:group],
        rank: entry[:rank], share_pct: entry[:share_pct], cum_pct: entry[:cum_pct],
        visits_30d: metric.visits_30d, units_30d: metric.units_30d,
        units_change_pct: entry[:units_change_pct], units_change_state: entry[:units_change_state],
        is_new: entry[:is_new], conversion_30d: metric.conversion_30d&.to_f, revenue_30d: metric.revenue_30d.to_f,
        profit_month: month[:profit], profit_is_before_cost: month[:profit_is_before_cost],
        margin_pct: month[:margin_pct], margin_state: month[:margin_state],
        suggestions_count: entry[:suggestions].size,
        urgent_count: entry[:suggestions].count { |s| s[:priority] == 1 },
        profit_state: month[:profit_state]
      }
    end

    def detail_payload(entry)
      metric = entry[:metric]
      item = entry[:item]

      {
        indicators: {
          visits: metric.visits_30d, prev_visits: metric.prev_visits_30d,
          units: metric.units_30d, prev_units: metric.prev_units_30d,
          conversion: metric.conversion_30d&.to_f, revenue: metric.revenue_30d.to_f,
          share_pct: entry[:share_pct], cum_pct: entry[:cum_pct]
        },
        month: entry[:economics].month,
        unit: entry[:economics].unit,
        listing: {
          stock: metric.stock, pictures: item&.pictures_count, has_video: item&.has_video,
          description_len: item&.description_len, title_len: metric.title.to_s.length,
          quality_score: item&.quality_score, listing_type_label: Painel::Labels.listing_type(metric.listing_type)
        },
        price: entry[:price], suggestions: entry[:suggestions], links: Painel::Labels.links(metric.item_id)
      }
    end

    def context_payload(entry)
      metric = entry[:metric]
      item = entry[:item]

      {
        brand: item&.brand, model: item&.model,
        attrs_missing_required: item&.attrs_missing_required || [],
        attrs_missing_main: item&.attrs_missing_main || [],
        quality_pending: item&.quality_pending || [],
        free_shipping: metric.free_shipping,
        tax_pct: @params.tax_pct, min_margin_pct: @params.min_margin_pct,
        conversion_median: entry[:conversion_median]
      }
    end
  end
end
