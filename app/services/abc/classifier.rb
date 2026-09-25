# SPEC 8.1/8.2 — universo, ordenação, curva A/B/C, grupos da curva A e
# mediana da conversão 30d. Recebe `rows` (qualquer coisa que responda aos
# métodos de `item_metrics`: item_id, status, revenue_30d, prev_revenue_30d,
# units_30d, prev_units_30d, visits_30d, conversion_30d — ItemMetric ou um
# Struct de teste) e `params` (Abc::Params). Serviço puro: nada de banco.
module Abc
  class Classifier
    ClassifiedRow = Struct.new(
      :metric, :rank, :share_pct, :cum_pct, :curve, :group,
      :units_change_pct, :units_change_state, :is_new,
      keyword_init: true
    )

    Result = Struct.new(:rows, :summary, :groups, :conversion_median, keyword_init: true)

    EXCLUDED_STATUSES = %w[closed inactive].freeze
    CURVES = %w[A B C].freeze
    GROUP_LABELS = { up: "Vendendo", flat: "Estagnados", down: "Em queda" }.freeze
    MEDIAN_MIN_VISITS = 100

    def self.call(rows, params) = new(rows, params).call

    def initialize(rows, params)
      @rows = rows
      @params = params
    end

    def call
      universe = @rows.reject { |row| excluded?(row) }
      ordered = universe.sort_by { |row| sort_key(row) }
      total_revenue = ordered.sum { |row| row.revenue_30d.to_f }

      classified = classify(ordered, total_revenue)

      Result.new(
        rows: classified,
        summary: summary_for(classified, total_revenue),
        groups: groups_for(classified),
        conversion_median: median_conversion(universe)
      )
    end

    private

    def excluded?(row)
      EXCLUDED_STATUSES.include?(row.status.to_s) &&
        (row.revenue_30d.to_f + row.prev_revenue_30d.to_f).zero?
    end

    def sort_key(row)
      [ -row.revenue_30d.to_f, -row.units_30d.to_i, -row.visits_30d.to_i, row.item_id.to_s ]
    end

    def classify(ordered, total_revenue)
      cumulative = 0.0

      ordered.each_with_index.map do |row, index|
        share_pct = total_revenue.zero? ? 0.0 : (row.revenue_30d.to_f / total_revenue * 100)
        cum_before = cumulative
        cum_pct = cum_before + share_pct
        cumulative = cum_pct

        change_pct, is_new = units_change(row)
        curve = curve_for(row, cum_before)

        ClassifiedRow.new(
          metric: row,
          rank: index + 1,
          share_pct: share_pct,
          cum_pct: cum_pct,
          curve: curve,
          group: curve == "A" ? group_for(change_pct, is_new) : nil,
          units_change_pct: change_pct,
          units_change_state: units_change_state(change_pct, is_new),
          is_new: is_new
        )
      end
    end

    def curve_for(row, cum_before)
      return "C" if row.revenue_30d.to_f.zero?
      return "A" if cum_before < @params.cut_a
      return "B" if cum_before < @params.cut_b

      "C"
    end

    # [variação_%, is_new]. Sem venda em nenhum dos dois períodos: [nil, false]
    # (não dá pra dizer se subiu ou caiu). Sem venda anterior e com venda
    # agora: "novo", conta como alta mas sem % definido.
    def units_change(row)
      units = row.units_30d.to_i
      prev_units = row.prev_units_30d.to_i

      return [ nil, false ] if prev_units.zero? && units.zero?
      return [ nil, true ] if prev_units.zero?

      [ (units - prev_units).to_f / prev_units * 100, false ]
    end

    def units_change_state(change_pct, is_new)
      return "ok" if is_new
      return nil if change_pct.nil?
      return "ok" if change_pct >= @params.up_pct
      return "bad" if change_pct < @params.down_pct

      nil
    end

    def group_for(change_pct, is_new)
      return "up" if is_new
      return "flat" if change_pct.nil?
      return "up" if change_pct >= @params.up_pct
      return "down" if change_pct < @params.down_pct

      "flat"
    end

    def summary_for(classified, total_revenue)
      CURVES.map do |curve|
        rows = classified.select { |row| row.curve == curve }
        revenue = rows.sum { |row| row.metric.revenue_30d.to_f }
        share = total_revenue.zero? ? 0.0 : (revenue / total_revenue * 100)
        { curve: curve, count: rows.size, revenue: revenue, share_pct: share }
      end
    end

    def groups_for(classified)
      curve_a = classified.select { |row| row.curve == "A" }

      %i[up flat down].index_with do |key|
        rows = curve_a.select { |row| row.group == key.to_s }
        {
          label: GROUP_LABELS[key],
          description: group_description(key),
          count: rows.size,
          revenue: rows.sum { |row| row.metric.revenue_30d.to_f }
        }
      end
    end

    def group_description(key)
      case key
      when :up then "Vendas em alta na curva A (variação ≥ #{@params.up_pct}%)."
      when :down then "Vendas em queda na curva A (variação < #{@params.down_pct}%)."
      else "Vendas estáveis na curva A (entre #{@params.down_pct}% e #{@params.up_pct}%)."
      end
    end

    def median_conversion(universe)
      values = universe
        .select { |row| row.visits_30d.to_i >= MEDIAN_MIN_VISITS }
        .filter_map { |row| row.conversion_30d&.to_f }
        .sort

      return nil if values.empty?

      mid = values.size / 2
      values.size.odd? ? values[mid] : (values[mid - 1] + values[mid]) / 2.0
    end
  end
end
