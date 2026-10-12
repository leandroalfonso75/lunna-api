require "rails_helper"

RSpec.describe Olist::SyncCosts do
  let(:company) { create(:company) }
  let(:connection) { create(:olist_connection, company: company) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }

  def product(olist_id, **attrs)
    create(:olist_product, company: company, olist_id: olist_id, variation_kind: "N", status: "A", stock_balance: 10, **attrs)
  end

  def movement(id, tipo, qty, preco: nil, data: "2026-01-0#{id} 10:00:00", deposito: 1)
    { "id" => id, "idDeposito" => deposito, "tipo" => tipo, "quantidade" => qty, "preco" => preco, "data" => data, "origem" => "api" }
  end

  def stub_movements(id, items)
    stub_request(:get, "#{base}/estoque/#{id}/logs-movimentacao").with(query: hash_including({ "limit" => "100" }))
      .to_return(status: 200, body: { itens: items, paginacao: { total: items.size } }.to_json)
  end

  it "guarda as movimentações e o custo PEPS do produto" do
    p1 = product(1, stock_deposits: [ { "id" => 1, "desconsiderar" => false }, { "id" => 7, "desconsiderar" => true } ])
    stub_movements(1, [ movement(1, "E", 10, preco: 5), movement(2, "E", 10, preco: 8), movement(3, "S", 10), movement(4, "E", 3, preco: 1, deposito: 7) ])

    described_class.new(connection).call

    p1.reload
    expect(p1).to have_attributes(fifo_unit_cost: 8, fifo_units: 10, fifo_units_without_cost: 0, fifo_stock_value: 80)
    expect(p1.fifo_layers.first).to include("remaining" => 10.0, "unit_cost" => 8.0)
    expect(p1.movements_synced_at).to be_present
    expect(OlistStockMovement.where(olist_product_id: 1).count).to eq(4)
    expect(connection.reload.costs_status).to eq("ok")
  end

  it "entrada sem custo ainda em estoque marca o aviso; consumida, não" do
    with_warning = product(1)
    without_warning = product(2)
    stub_movements(1, [ movement(1, "E", 10, preco: nil) ])
    stub_movements(2, [ movement(1, "E", 10, preco: nil), movement(2, "E", 10, preco: 6), movement(3, "S", 10) ])

    described_class.new(connection).call

    expect(with_warning.reload.fifo_units_without_cost).to eq(10)
    expect(with_warning.fifo_unit_cost).to be_nil
    expect(without_warning.reload.fifo_units_without_cost).to eq(0)
    expect(without_warning.fifo_unit_cost).to eq(6)
  end

  it "relê um produto substituindo as movimentações antigas (sem duplicar)" do
    p1 = product(1)
    stub_movements(1, [ movement(1, "E", 10, preco: 5) ])
    described_class.new(connection).call

    p1.update!(stock_balance: 4) # saldo mudou: precisa recalcular
    stub_movements(1, [ movement(1, "E", 10, preco: 5), movement(2, "S", 6) ])
    described_class.new(connection).call

    expect(OlistStockMovement.where(olist_product_id: 1).count).to eq(2)
    expect(p1.reload).to have_attributes(fifo_units: 4, fifo_balance_at_calc: 4)
  end

  it "não relê produto cujo saldo não mudou e foi lido há pouco" do
    product(1)
    stub = stub_movements(1, [ movement(1, "E", 10, preco: 5) ])

    described_class.new(connection).call
    described_class.new(connection).call

    expect(stub).to have_been_requested.once
  end

  it "ignora pais de variação e produtos excluídos" do
    product(1, variation_kind: "P")
    product(2, status: "E")

    described_class.new(connection).call

    expect(WebMock).not_to have_requested(:get, /logs-movimentacao/)
  end

  it "403: registra falta de permissão e não repete antes de 30 minutos" do
    product(1)
    stub = stub_request(:get, "#{base}/estoque/1/logs-movimentacao").with(query: hash_including({})).to_return(status: 403, body: "")

    described_class.new(connection).call
    described_class.new(connection.reload).call

    expect(connection.reload.costs_status).to eq("forbidden")
    expect(stub).to have_been_requested.once
  end

  it "volta a tentar depois de 30 minutos e se recupera quando a permissão chega" do
    p1 = product(1)
    connection.update!(costs_status: "forbidden", costs_checked_at: 31.minutes.ago)
    stub_movements(1, [ movement(1, "E", 2, preco: 3) ])

    described_class.new(connection).call

    expect(connection.reload.costs_status).to eq("ok")
    expect(p1.reload.fifo_unit_cost).to eq(3)
  end

  it "falha em um produto não impede os outros" do
    product(1)
    p2 = product(2)
    stub_request(:get, "#{base}/estoque/1/logs-movimentacao").with(query: hash_including({})).to_return(status: 500, body: "x")
    stub_movements(2, [ movement(1, "E", 2, preco: 3) ])
    allow_any_instance_of(Olist::Client).to receive(:sleep)

    described_class.new(connection).call

    expect(p2.reload.fifo_unit_cost).to eq(3)
    expect(connection.reload.costs_status).to eq("error")
  end

  it "processa em lotes de 40 produtos por vez" do
    (1..45).each { |i| product(i) }
    (1..45).each { |i| stub_movements(i, [ movement(1, "E", 1, preco: 2) ]) }

    described_class.new(connection).call

    expect(OlistProduct.where(company: company).where.not(movements_synced_at: nil).count).to eq(40)
  end

  it "o job só roda uma conexão ativa e é enfileirado ao fim do sync de produtos" do
    ActiveJob::Base.queue_adapter = :test
    stub_request(:get, "#{base}/produtos").with(query: hash_including({}))
      .to_return(status: 200, body: { itens: [], paginacao: { total: 0 } }.to_json)
    stub_request(:get, "#{base}/estoque").with(query: hash_including({}))
      .to_return(status: 200, body: { itens: [], paginacao: { total: 0 } }.to_json)

    expect { Olist::SyncJob.perform_now(connection.id) }.to have_enqueued_job(Olist::SyncCostsJob).with(connection.id)
  end
end
