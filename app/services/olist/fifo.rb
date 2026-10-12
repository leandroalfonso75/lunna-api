# Custo pelo método PEPS (Primeiro que Entra, Primeiro que Sai) a partir das
# movimentações de estoque do Olist. Função pura: não acessa banco nem rede.
#
# - Cada ENTRADA (tipo E) vira uma "camada" com a quantidade e o custo unitário
#   informado nela. Cada SAÍDA (S) consome as camadas da mais antiga para a mais nova.
# - BALANÇO (B) define o saldo do depósito: se o saldo sobe, a diferença entra como
#   camada (com o preço do balanço); se desce, a diferença sai.
# - Custo ausente = preço vazio ou zero. Só gera aviso se a camada AINDA tiver unidades
#   em estoque: entrada sem custo que já foi toda consumida é ignorada.
# - O custo do produto é o da camada mais antiga que ainda tem saldo (a próxima a sair).
module Olist
  class Fifo
    Layer = Struct.new(:id, :moved_at, :quantity, :remaining, :unit_cost, :origin, keyword_init: true) do
      def costed? = !unit_cost.nil?
    end

    Result = Struct.new(:layers, :unit_cost, :stock_value, :units, :units_without_cost, :shortfall, :balance, :last_entry_cost,
      keyword_init: true) do
      def warning? = units_without_cost.positive?
    end

    # movements: [{ id:, deposit_id:, kind: "E|S|B", quantity:, price:, moved_at:, origin: }]
    # ignored_deposit_ids: depósitos que o Olist não conta no saldo (ex.: Full ML).
    def self.call(movements, ignored_deposit_ids: [])
      new(movements, ignored_deposit_ids).call
    end

    def initialize(movements, ignored_deposit_ids)
      @movements = movements.reject { |m| ignored_deposit_ids.include?(m[:deposit_id]) }
      @layers = []
      @balances = Hash.new(BigDecimal("0"))
      @shortfall = BigDecimal("0")
      @last_entry_cost = nil
    end

    def call
      sorted.each { |movement| apply(movement) }
      build_result
    end

    private

    def sorted
      @movements.sort_by { |m| [ m[:moved_at] || Time.zone.at(0), m[:id].to_i ] }
    end

    def apply(movement)
      quantity = decimal(movement[:quantity])
      deposit = movement[:deposit_id]

      case movement[:kind]
      when "E"
        add_layer(movement, quantity)
        @balances[deposit] += quantity
      when "S"
        consume(quantity)
        @balances[deposit] -= quantity
      when "B"
        delta = quantity - @balances[deposit]
        add_layer(movement, delta) if delta.positive?
        consume(-delta) if delta.negative?
        @balances[deposit] = quantity
      end
    end

    def add_layer(movement, quantity)
      return unless quantity.positive?

      cost = decimal(movement[:price])
      cost = nil unless cost.positive?
      @layers << Layer.new(id: movement[:id], moved_at: movement[:moved_at], quantity: quantity, remaining: quantity,
        unit_cost: cost, origin: movement[:origin])
      @last_entry_cost = cost if cost
    end

    def consume(quantity)
      left = quantity
      @layers.each do |layer|
        break unless left.positive?
        next unless layer.remaining.positive?

        used = [ layer.remaining, left ].min
        layer.remaining -= used
        left -= used
      end
      @shortfall += left if left.positive?
    end

    def build_result
      open = @layers.select { |layer| layer.remaining.positive? }
      costed = open.select(&:costed?)

      Result.new(
        layers: open,
        unit_cost: open.first&.unit_cost,
        stock_value: costed.sum { |layer| layer.remaining * layer.unit_cost },
        units: open.sum(&:remaining),
        units_without_cost: open.reject(&:costed?).sum(&:remaining),
        shortfall: @shortfall,
        balance: @balances.values.sum,
        last_entry_cost: @last_entry_cost
      )
    end

    def decimal(value)
      BigDecimal(value.to_s.presence || "0")
    rescue ArgumentError
      BigDecimal("0")
    end
  end
end
