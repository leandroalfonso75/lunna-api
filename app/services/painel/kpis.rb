# Seis cartões do cabeçalho (SPEC 7.2), na ordem exata da tabela da SPEC.
module Painel
  class Kpis
    # `daily` é o array já calculado por Painel::Daily (mesma fonte do
    # gráfico, pra "Hoje até agora" não recalcular revenue/pedidos de novo).
    def self.call(metrics, daily) = new(metrics, daily).call

    def initialize(metrics, daily)
      @metrics = metrics
      @today = daily.last
    end

    def call
      [ today_card, units_7d_card, revenue_7d_card, visits_7d_card, conversion_7d_card, stock_active_card ]
    end

    private

    def today_card
      {
        key: "today", label: "Hoje até agora", value: @today[:revenue], value_type: "money",
        sub_label: "#{@today[:units]} un. · #{@today[:orders]} pedidos", delta: nil
      }
    end

    def units_7d_card
      current = @metrics.sum(:units_7d)
      previous = @metrics.sum(:prev_units_7d)

      { key: "units_7d", label: "Vendas · 7 dias", value: current, value_type: "int",
        sub_label: nil, delta: pct_delta(current, previous) }
    end

    def revenue_7d_card
      current = @metrics.sum(:revenue_7d).to_f
      previous = @metrics.sum(:prev_revenue_7d).to_f

      { key: "revenue_7d", label: "Faturado · 7 dias", value: current, value_type: "money",
        sub_label: nil, delta: pct_delta(current, previous) }
    end

    def visits_7d_card
      current = @metrics.sum(:visits_7d)
      previous = @metrics.sum(:prev_visits_7d)

      { key: "visits_7d", label: "Visitas · 7 dias", value: current, value_type: "int",
        sub_label: nil, delta: pct_delta(current, previous) }
    end

    def conversion_7d_card
      units = @metrics.sum(:units_7d)
      visits = @metrics.sum(:visits_7d)
      prev_units = @metrics.sum(:prev_units_7d)
      prev_visits = @metrics.sum(:prev_visits_7d)

      { key: "conversion_7d", label: "Conversão", value: ratio(units, visits), value_type: "pct",
        sub_label: nil, delta: pp_delta(ratio(units, visits), ratio(prev_units, prev_visits)) }
    end

    def stock_active_card
      active = @metrics.where(status: "active")

      { key: "stock_active", label: "Estoque dos ativos", value: active.sum(:stock), value_type: "int",
        sub_label: "#{active.where(full: true).count} anúncios no Full", delta: nil }
    end

    def ratio(count, total)
      return nil if total.to_i.zero?

      (count.to_f / total * 100).round(2)
    end

    def pct_delta(current, previous)
      return nil if previous.blank? || previous.zero?

      value = ((current - previous) / previous.to_f * 100).round(1)
      { value: value, unit: "pct", direction: direction(value) }
    end

    def pp_delta(current, previous)
      return nil if current.nil? || previous.nil?

      value = (current - previous).round(1)
      { value: value, unit: "pp", direction: direction(value) }
    end

    def direction(value)
      return "flat" if value.abs < 0.5

      value.positive? ? "up" : "down"
    end
  end
end
