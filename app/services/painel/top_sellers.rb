# Top 10 por vendas 7d, desempate pela semana anterior (SPEC 7.4). Só quem
# vendeu em alguma das duas semanas. Barras na escala do maior valor entre
# todas as linhas devolvidas (pra ficarem comparáveis no mesmo gráfico).
module Painel
  class TopSellers
    LIMIT = 10

    def self.call(metrics) = new(metrics).call

    def initialize(metrics)
      @metrics = metrics
    end

    def call
      rows = @metrics.where("units_7d > 0 OR prev_units_7d > 0")
        .order(units_7d: :desc, prev_units_7d: :desc)
        .limit(LIMIT)
        .pluck(:item_id, :title, :units_7d, :prev_units_7d)

      max = [ rows.flat_map { |(_id, _title, units, prev_units)| [ units, prev_units ] }.max.to_f, 1.0 ].max

      rows.map do |item_id, title, units, prev_units|
        {
          id: item_id, title: title, units_week: units, units_prev_week: prev_units,
          bar_pct: (units / max * 100).round(1), bar_prev_pct: (prev_units / max * 100).round(1)
        }
      end
    end
  end
end
