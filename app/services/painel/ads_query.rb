# Seção Ads: resumo, série diária, campanhas e anúncios de Product Ads do Mercado Livre.
#
# Métricas derivadas (sempre recalculadas aqui, nunca somadas entre campanhas):
#   ACOS = investimento ÷ vendas por ads × 100      ROAS = vendas por ads ÷ investimento
#   CTR = cliques ÷ impressões × 100                CPC = investimento ÷ cliques
#   Conversão = unidades vendidas por ads ÷ cliques × 100
module Painel
  class AdsQuery
    PRESETS = { "7d" => 7, "30d" => 30, "60d" => 60, "90d" => 90 }.freeze
    DEFAULT_PERIOD = "30d"
    MAX_DAYS = 90
    ITEM_WINDOWS = [ [ 7, "7d" ], [ 30, "30d" ], [ MAX_DAYS, "90d" ] ].freeze
    PER_PAGES = [ 25, 50, 100 ].freeze
    ITEM_SORTS = %w[cost total_amount acos roas clicks prints units title price].freeze
    MIN_COST_TO_FLAG = 10.0

    CAMPAIGN_STATUS = {
      "active" => [ "Ativa", "ok" ], "paused" => [ "Pausada", "warn" ], "hold" => [ "Em espera", "warn" ],
      "idle" => [ "Sem anúncios", "neutral" ], "delegated" => [ "Delegada", "neutral" ]
    }.freeze

    STRATEGIES = {
      "PROFITABILITY" => "Rentabilidade", "INCREASE" => "Crescimento", "VISIBILITY" => "Visibilidade", "AUTOMATIC" => "Automática"
    }.freeze

    METRIC_FIELDS = {
      "clicks" => :clicks, "prints" => :prints, "cost" => :cost, "total_amount" => :total_amount,
      "direct_amount" => :direct_amount, "indirect_amount" => :indirect_amount, "units" => :units,
      "direct_units" => :direct_units, "indirect_units" => :indirect_units, "organic_units" => :organic_units,
      "organic_amount" => :organic_amount
    }.freeze

    def self.call(account, params)
      new(account, params).call
    end

    def self.items(account, params)
      new(account, params).items
    end

    def initialize(account, params)
      @account = account
      @params = params
      @today = Date.current
    end

    def call
      from, to = window
      rows = daily_rows(from, to)
      campaigns = @account.ml_ad_campaigns.to_a
      by_campaign = rows.group_by(&:campaign_id)

      {
        period: { from: from.iso8601, to: to.iso8601, preset: preset_key, days: (to - from).to_i + 1 },
        summary: derive(sum(rows)),
        previous: previous_summary(from, to),
        daily: daily_series(rows, from, to),
        campaigns: campaigns.map { |c| campaign_payload(c, by_campaign[c.campaign_id] || []) }
          .sort_by { |c| [ c[:status][:key] == "active" ? 0 : 1, -c[:metrics][:cost] ] },
        sync: sync_info
      }
    end

    def items
      window_key = item_window_key
      campaigns = @account.ml_ad_campaigns.index_by(&:campaign_id)
      scope = @account.ml_ad_items
      scope = scope.where(campaign_id: @params[:campaign_id]) if @params[:campaign_id].present?
      scope = scope.where(status: @params[:status]) if %w[active paused].include?(@params[:status].to_s)
      scope = apply_search(scope)

      rows = scope.to_a.map { |item| item_payload(item, window_key, campaigns) }
      rows = rows.select { |r| r[:flag] && r[:flag][:key] == @params[:flag].to_s } if @params[:flag].present?
      sorted = sort_items(rows)
      page, per = paging

      {
        window: window_key, items: sorted.slice((page - 1) * per, per) || [], total: sorted.size, page: page, per_page: per,
        sort: item_sort, dir: item_dir,
        totals: derive(sum_hashes(rows.map { |r| r[:metrics] })),
        flags: rows.filter_map { |r| r[:flag]&.dig(:key) }.tally
      }
    end

    private

    # --- período ---

    def preset_key
      return "custom" if custom_dates?

      PRESETS.key?(@params[:period].to_s) ? @params[:period].to_s : DEFAULT_PERIOD
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
      earliest = @today - (MAX_DAYS - 1)
      if custom_dates?
        from = [ parse_date(@params[:from]), earliest ].max
        to = [ parse_date(@params[:to]), @today ].min
        return [ from, [ to, from ].max ]
      end

      [ @today - (PRESETS.fetch(preset_key) - 1), @today ]
    end

    # --- métricas ---

    def daily_rows(from, to)
      @account.ml_ad_daily_metrics.where(date: from..to).to_a
    end

    def sum(rows)
      METRIC_FIELDS.each_with_object({}) { |(key, attr), acc| acc[key.to_sym] = rows.sum { |r| r.public_send(attr).to_f } }
    end

    def sum_hashes(hashes)
      %i[clicks prints cost total_amount direct_amount indirect_amount units direct_units indirect_units organic_units
         organic_amount].index_with { |key| hashes.sum { |h| h[key].to_f } }
    end

    def derive(m)
      cost = m[:cost].to_f
      amount = m[:total_amount].to_f
      clicks = m[:clicks].to_f
      prints = m[:prints].to_f
      m.merge(
        clicks: m[:clicks].to_i, prints: m[:prints].to_i, units: m[:units].to_i,
        cost: cost.round(2), total_amount: amount.round(2),
        acos: amount.positive? ? (cost / amount * 100).round(2) : nil,
        roas: cost.positive? ? (amount / cost).round(2) : nil,
        ctr: prints.positive? ? (clicks / prints * 100).round(2) : nil,
        cpc: clicks.positive? ? (cost / clicks).round(2) : nil,
        cvr: clicks.positive? ? (m[:units].to_f / clicks * 100).round(2) : nil
      )
    end

    def previous_summary(from, to)
      days = (to - from).to_i + 1
      prev_to = from - 1
      prev_from = prev_to - (days - 1)
      return nil if prev_from < @today - (MAX_DAYS - 1)

      rows = daily_rows(prev_from, prev_to)
      return nil if rows.empty?

      derive(sum(rows))
    end

    def daily_series(rows, from, to)
      by_date = rows.group_by(&:date)
      (from..to).map do |date|
        day = by_date[date] || []
        { date: date.iso8601, cost: day.sum { |r| r.cost.to_f }.round(2), total_amount: day.sum { |r| r.total_amount.to_f }.round(2),
          clicks: day.sum(&:clicks), units: day.sum(&:units) }
      end
    end

    def campaign_payload(campaign, rows)
      metrics = derive(sum(rows))
      label, tone = CAMPAIGN_STATUS.fetch(campaign.status, [ campaign.status.to_s, "neutral" ])
      {
        id: campaign.campaign_id, name: campaign.name, status: { key: campaign.status, label: label, tone: tone },
        strategy: STRATEGIES.fetch(campaign.strategy, campaign.strategy), channel: campaign.channel,
        acos_target: campaign.acos_target&.to_f, roas_target: campaign.roas_target&.to_f,
        daily_budget: campaign.daily_budget&.to_f, budget: campaign.budget&.to_f, automatic_budget: campaign.automatic_budget,
        date_created: campaign.date_created, last_updated: campaign.last_updated,
        metrics: metrics, acos_state: acos_state(metrics[:acos], campaign.acos_target&.to_f, metrics[:cost]),
        ads_count: ads_counts[campaign.campaign_id].to_i,
        daily: daily_series(rows, window.first, window.last).map { |d| d.slice(:date, :cost, :total_amount) }
      }
    end

    def ads_counts
      @ads_counts ||= @account.ml_ad_items.group(:campaign_id).count
    end

    # ok = dentro da meta, warn = até 20% acima, bad = acima disso (sem meta ou sem venda: neutral/bad)
    def acos_state(acos, target, cost)
      return "neutral" if cost.to_f <= 0
      return "bad" if acos.nil?
      return "neutral" if target.nil? || target.zero?

      if acos <= target then "ok"
      elsif acos <= target * 1.2 then "warn"
      else "bad"
      end
    end

    # --- anúncios ---

    def item_window_key
      days = custom_dates? ? MAX_DAYS : PRESETS.fetch(preset_key)
      ITEM_WINDOWS.find { |limit, _| days <= limit }&.last || "90d"
    end

    def item_payload(item, window_key, campaigns)
      raw = item.metrics[window_key] || {}
      metrics = derive(
        clicks: raw["clicks"].to_i, prints: raw["prints"].to_i, cost: raw["cost"].to_f, total_amount: raw["total_amount"].to_f,
        direct_amount: raw["direct_amount"].to_f, indirect_amount: raw["indirect_amount"].to_f, units: raw["units_quantity"].to_i,
        direct_units: raw["direct_units_quantity"].to_i, indirect_units: raw["indirect_units_quantity"].to_i,
        organic_units: raw["organic_units_quantity"].to_i, organic_amount: raw["organic_units_amount"].to_f
      )
      campaign = campaigns[item.campaign_id]
      {
        item_id: item.item_id, title: item.title, thumbnail: item.thumbnail, permalink: item.permalink, price: item.price&.to_f,
        status: item.status, status_label: { "active" => "Ativo", "paused" => "Pausado" }.fetch(item.status, item.status),
        campaign: { id: item.campaign_id, name: campaign&.name || "Campanha encerrada", status: campaign&.status },
        listing_type: item.listing_type_id, logistic_type: item.logistic_type, catalog: item.catalog_listing,
        buy_box_winner: item.buy_box_winner, recommended: item.recommended, has_discount: item.has_discount,
        metrics: metrics, flag: item_flag(metrics, campaign)
      }
    end

    # Sinais para a tela: gastou e não vendeu, ACOS acima da meta da campanha, ou performando bem.
    def item_flag(metrics, campaign)
      cost = metrics[:cost]
      return nil if cost < MIN_COST_TO_FLAG && metrics[:units].zero?
      return { key: "sem_venda", label: "Gastou e não vendeu", tone: "bad" } if cost >= MIN_COST_TO_FLAG && metrics[:units].zero?

      target = campaign&.acos_target&.to_f
      return nil if target.nil? || target.zero? || metrics[:acos].nil?
      return { key: "acos_alto", label: "ACOS acima da meta", tone: "warn" } if metrics[:acos] > target * 1.2

      { key: "bom", label: "Dentro da meta", tone: "ok" } if metrics[:acos] <= target
    end

    def apply_search(scope)
      q = @params[:q].to_s.strip
      return scope if q.empty?

      like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      scope.where("title ILIKE :like OR item_id ILIKE :like", like: like)
    end

    def item_sort = ITEM_SORTS.include?(@params[:sort].to_s) ? @params[:sort].to_s : "cost"
    def item_dir = @params[:dir].to_s == "asc" ? "asc" : "desc"

    def sort_items(rows)
      key = item_sort
      rows.sort_by do |r|
        value = case key
        when "title" then r[:title].to_s.downcase
        when "price" then r[:price]
        else r[:metrics][key.to_sym]
        end
        nil_last = value.nil? ? 1 : 0
        if value.is_a?(String)
          # strings: ordem alfabética; descendente por inversão de bytes
          [ nil_last, item_dir == "asc" ? value : value.unpack("C*").map { |b| -b } ]
        else
          [ nil_last, item_dir == "asc" ? (value || 0) : -(value || 0) ]
        end
      end
    end

    def paging
      per = @params[:per_page].to_i
      per = 50 unless PER_PAGES.include?(per)
      [ [ @params[:page].to_i, 1 ].max, per ]
    end

    def sync_info
      { last_sync_at: @account.ads_synced_at, campaigns: @account.ml_ad_campaigns.count, ads: @account.ml_ad_items.count }
    end
  end
end
