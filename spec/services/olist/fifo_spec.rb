require "rails_helper"

RSpec.describe Olist::Fifo do
  def move(id, kind, quantity, price: nil, day: id, deposit: 1, origin: nil)
    { id: id, deposit_id: deposit, kind: kind, quantity: quantity, price: price, moved_at: Time.utc(2026, 1, 1) + day.days, origin: origin }
  end

  def run(moves, **opts) = described_class.call(moves, **opts)

  it "sem movimentações: nada em estoque, sem custo e sem aviso" do
    result = run([])

    expect(result).to have_attributes(unit_cost: nil, units: 0, stock_value: 0, balance: 0)
    expect(result.warning?).to be false
  end

  it "uma entrada com custo: o custo do produto é o dela" do
    result = run([ move(1, "E", 10, price: 5.5) ])

    expect(result).to have_attributes(unit_cost: 5.5, units: 10, stock_value: 55)
    expect(result.layers.size).to eq(1)
  end

  it "as saídas consomem da camada mais antiga: o custo passa a ser o da próxima" do
    result = run([ move(1, "E", 10, price: 5), move(2, "E", 10, price: 8), move(3, "S", 12) ])

    expect(result.units).to eq(8)
    expect(result.unit_cost).to eq(8)
    expect(result.layers.map { |l| [ l.remaining, l.unit_cost ] }).to eq([ [ 8, 8 ] ])
    expect(result.stock_value).to eq(64)
  end

  it "saída que consome só parte da camada mais antiga mantém o custo dela" do
    result = run([ move(1, "E", 10, price: 5), move(2, "E", 10, price: 8), move(3, "S", 4) ])

    expect(result.unit_cost).to eq(5)
    expect(result.layers.map(&:remaining)).to eq([ 6, 10 ])
    expect(result.stock_value).to eq(6 * 5 + 10 * 8)
  end

  it "ordena por data (e id), não pela ordem em que chegam" do
    result = run([ move(3, "S", 10, day: 3), move(2, "E", 10, price: 8, day: 2), move(1, "E", 10, price: 5, day: 1) ])

    expect(result.unit_cost).to eq(8)
    expect(result.units).to eq(10)
  end

  describe "aviso de entrada sem custo" do
    it "entrada sem custo AINDA em estoque gera aviso e custo indefinido" do
      result = run([ move(1, "E", 10, price: nil), move(2, "E", 5, price: 9) ])

      expect(result.warning?).to be true
      expect(result.units_without_cost).to eq(10)
      expect(result.unit_cost).to be_nil
      expect(result.stock_value).to eq(45)
    end

    it "preço zero também conta como custo não informado" do
      expect(run([ move(1, "E", 3, price: 0) ]).units_without_cost).to eq(3)
    end

    it "entrada sem custo toda consumida é desconsiderada (sem aviso)" do
      result = run([ move(1, "E", 10, price: nil), move(2, "E", 10, price: 7), move(3, "S", 10) ])

      expect(result.warning?).to be false
      expect(result.unit_cost).to eq(7)
      expect(result.units).to eq(10)
    end

    it "entrada sem custo parcialmente consumida ainda avisa pelo que sobrou" do
      result = run([ move(1, "E", 10, price: nil), move(2, "S", 4) ])

      expect(result.warning?).to be true
      expect(result.units_without_cost).to eq(6)
    end
  end

  describe "balanço" do
    it "balanço acima do saldo entra a diferença como camada, com o preço do balanço" do
      result = run([ move(1, "E", 10, price: 5), move(2, "B", 15, price: 6) ])

      expect(result.units).to eq(15)
      expect(result.layers.map { |l| [ l.remaining, l.unit_cost ] }).to eq([ [ 10, 5 ], [ 5, 6 ] ])
    end

    it "balanço abaixo do saldo dá saída da diferença (da camada mais antiga)" do
      result = run([ move(1, "E", 10, price: 5), move(2, "E", 10, price: 8), move(3, "B", 12) ])

      expect(result.units).to eq(12)
      expect(result.layers.map { |l| [ l.remaining, l.unit_cost ] }).to eq([ [ 2, 5 ], [ 10, 8 ] ])
    end

    it "balanço sem preço, quando sobe, é entrada sem custo (avisa)" do
      result = run([ move(1, "B", 5, price: nil) ])

      expect(result.units_without_cost).to eq(5)
    end

    it "balanço é por depósito" do
      result = run([ move(1, "E", 10, price: 5, deposit: 1), move(2, "B", 4, price: 7, deposit: 2) ])

      expect(result.units).to eq(14)
    end
  end

  it "saída maior que as entradas conhecidas vira diferença (histórico incompleto)" do
    result = run([ move(1, "E", 5, price: 5), move(2, "S", 8) ])

    expect(result.units).to eq(0)
    expect(result.shortfall).to eq(3)
  end

  it "ignora depósitos fora do saldo (Full ML)" do
    result = run([ move(1, "E", 10, price: 5, deposit: 1), move(2, "E", 99, price: 1, deposit: 7) ], ignored_deposit_ids: [ 7 ])

    expect(result.units).to eq(10)
    expect(result.unit_cost).to eq(5)
  end

  describe "Full do Mercado Livre (depósito razão)" do
    def mv(id, kind, qty, price: nil, deposit: 1, note: nil, day: id)
      { id: id, deposit_id: deposit, kind: kind, quantity: qty, price: price, moved_at: Time.utc(2026, 1, 1) + day.days, origin: nil, note: note }
    end

    it "envio do Geral ao Full (observação 'Envio ...') não consome camadas, só baixa o saldo do Geral" do
      result = run([ mv(1, "E", 100, price: 5), mv(2, "S", 40, note: "Envio 3 - 2-3-26") ], ledger_deposit_ids: [ 7 ])

      expect(result.units).to eq(100)
      expect(result.balance).to eq(60)
      expect(result.layers.first.remaining).to eq(100)
    end

    it "NFT e 'Envio Full' também são transferência" do
      result = run([ mv(1, "E", 50, price: 5), mv(2, "S", 10, note: "NFT 2-2"), mv(3, "S", 5, note: "Envio Full 1-2-3") ], ledger_deposit_ids: [ 7 ])

      expect(result.units).to eq(50)
    end

    it "venda registrada no depósito do Full consome as camadas mais antigas" do
      result = run(
        [ mv(1, "E", 10, price: 5), mv(2, "E", 10, price: 8), mv(3, "S", 10, note: "Envio 1", deposit: 1), mv(4, "S", 4, deposit: 7) ],
        ledger_deposit_ids: [ 7 ]
      )

      expect(result.units).to eq(16)
      expect(result.layers.map { |l| [ l.remaining, l.unit_cost ] }).to eq([ [ 6, 5 ], [ 10, 8 ] ])
      expect(result.unit_cost).to eq(5)
    end

    it "balanço no depósito do Full só zera o razão: não cria camada" do
      result = run([ mv(1, "E", 10, price: 5), mv(2, "S", 3, deposit: 7), mv(3, "B", 0, price: 0, deposit: 7) ], ledger_deposit_ids: [ 7 ])

      expect(result.units).to eq(7)
    end

    it "saída comum do Geral (sem nota de envio) continua sendo venda" do
      result = run([ mv(1, "E", 10, price: 5), mv(2, "S", 4, note: "Vendas Matriz 3/4") ], ledger_deposit_ids: [ 7 ])

      expect(result.units).to eq(6)
    end

    it "o mesmo texto no depósito do Full não é tratado como transferência" do
      result = run([ mv(1, "E", 10, price: 5), mv(2, "S", 4, deposit: 7, note: "Envio") ], ledger_deposit_ids: [ 7 ])

      expect(result.units).to eq(6)
    end
  end

  it "guarda o custo da última entrada informada, mesmo sem estoque" do
    result = run([ move(1, "E", 5, price: 4), move(2, "E", 5, price: 6), move(3, "S", 10) ])

    expect(result.units).to eq(0)
    expect(result.unit_cost).to be_nil
    expect(result.last_entry_cost).to eq(6)
  end

  it "aceita quantidade e preço como texto ou decimal" do
    result = run([ move(1, "E", "2.5", price: "3.20") ])

    expect(result.stock_value).to eq(BigDecimal("8.0"))
  end
end
