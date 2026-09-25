# Períodos de dias fechados no fuso de São Paulo (SPEC 6), sem contar hoje
# (exceto o próprio "hoje"). Usado por Painel::ItemMetrics pra saber as
# janelas e pelo PainelController pra montar o campo `period` da resposta.
module Painel
  class Periods
    # Continua sendo um Range de verdade (funciona com `cover?`, `include?`
    # etc.); só o `as_json` muda, pra sair como {from, to} ISO em vez do
    # `to_s` que o ActiveSupport usa por padrão em Range.
    class DateRange < Range
      def as_json(*) = { from: self.begin.iso8601, to: self.end.iso8601 }
    end

    def self.call(today = Date.current) = new(today).call

    def initialize(today)
      @today = today
    end

    def call
      {
        today: DateRange.new(@today, @today),
        week: DateRange.new(@today - 7, @today - 1),
        prev_week: DateRange.new(@today - 14, @today - 8),
        month: DateRange.new(@today - 30, @today - 1),
        prev_month: DateRange.new(@today - 60, @today - 31),
        daily: DateRange.new(@today - 14, @today)
      }
    end
  end
end
