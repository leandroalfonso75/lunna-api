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
# - Histórico que não fecha: se as saídas registradas superam as entradas (ou deixam menos unidades
#   do que o estoque real), o que está na prateleira só pode ser das compras mais recentes. Com o
#   estoque atual informado (`current_stock`), as camadas são refeitas a partir da entrada mais nova
#   para trás até cobrir esse estoque (`reconstructed`).
#
# Estoque no Full do Mercado Livre (depósito "Full ML" do Olist, que o Olist deixa fora do saldo):
# o estoque da empresa é Geral + Full, então tudo entra num único conjunto de camadas.
# - Saída do depósito Geral para o Full (observação "Envio ..." ou "NFT ...") é TRANSFERÊNCIA: baixa o saldo
#   do Geral, mas as unidades continuam da empresa e NÃO consomem camadas.
# - Venda registrada no depósito do Full (saídas) consome camadas normalmente.
# - Balanço no depósito do Full só zera o razão (o Olist registra só as saídas ali): não cria camada.
module Olist
  class Fifo
    Layer = Struct.new(:id, :moved_at, :quantity, :remaining, :unit_cost, :origin, keyword_init: true) do
      def costed? = !unit_cost.nil?
    end

    Result = Struct.new(:layers, :unit_cost, :stock_value, :units, :units_without_cost, :shortfall, :balance, :last_entry_cost,
      :reconstructed, keyword_init: true) do
      def warning? = units_without_cost.positive?
    end

    # movements: [{ id:, deposit_id:, kind: "E|S|B", quantity:, price:, moved_at:, origin: }]
    # ledger_deposit_ids: depósitos "razão" (Full ML), onde só as saídas (vendas) são registradas.
    # ignored_deposit_ids: depósitos a descartar por completo.
    def self.call(movements, ledger_deposit_ids: [], ignored_deposit_ids: [], current_stock: nil)
      new(movements, ledger_deposit_ids, ignored_deposit_ids, current_stock).call
    end

    # Observação que marca a saída do Geral como envio ao Full (transferência), não venda.
    TRANSFER_NOTE = /\A\s*(envio|nft)\b/i

    def initialize(movements, ledger_deposit_ids, ignored_deposit_ids, current_stock = nil)
      @current_stock = current_stock && decimal(current_stock)
      @ledger = ledger_deposit_ids
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
        consume(quantity) unless transfer?(movement)
        @balances[deposit] -= quantity unless ledger?(deposit)
      when "B"
        return if ledger?(deposit)

        delta = quantity - @balances[deposit]
        add_layer(movement, delta) if delta.positive?
        consume(-delta) if delta.negative?
        @balances[deposit] = quantity
      end
    end

    def ledger?(deposit) = @ledger.include?(deposit)

    # Envio do Geral ao Full: o estoque só mudou de lugar.
    def transfer?(movement)
      !ledger?(movement[:deposit_id]) && movement[:note].to_s.match?(TRANSFER_NOTE)
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
      reconstructed = false
      if @current_stock&.positive? && open.sum(&:remaining) < @current_stock && @layers.any?
        open = rebuild_from_newest(@current_stock)
        reconstructed = true
      end
      costed = open.select(&:costed?)

      Result.new(
        layers: open,
        unit_cost: open.first&.unit_cost,
        stock_value: costed.sum { |layer| layer.remaining * layer.unit_cost },
        units: open.sum(&:remaining),
        units_without_cost: open.reject(&:costed?).sum(&:remaining),
        shortfall: @shortfall,
        balance: @balances.values.sum,
        last_entry_cost: @last_entry_cost,
        reconstructed: reconstructed
      )
    end

    # Camadas que cobrem o estoque atual, da entrada mais nova para trás (devolvidas da mais antiga à mais nova).
    def rebuild_from_newest(stock)
      need = stock
      picked = []
      @layers.reverse_each do |layer|
        break unless need.positive?

        take = [ layer.quantity, need ].min
        picked << Layer.new(id: layer.id, moved_at: layer.moved_at, quantity: layer.quantity, remaining: take,
          unit_cost: layer.unit_cost, origin: layer.origin)
        need -= take
      end
      picked.reverse
    end

    def decimal(value)
      BigDecimal(value.to_s.presence || "0")
    rescue ArgumentError
      BigDecimal("0")
    end
  end
end
