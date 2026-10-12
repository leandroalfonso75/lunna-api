require "rails_helper"

RSpec.describe Olist::SyncProducts do
  let(:company) { create(:company) }
  let(:connection) { create(:olist_connection, company: company) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }
  let(:run) { described_class.start_run(connection, trigger: "auto").first }

  def product_item(id, sku:, price: 100.0)
    {
      "id" => id, "sku" => sku, "descricao" => "Produto #{sku}", "tipo" => "S", "situacao" => "A", "tipoVariacao" => "N",
      "unidade" => "UN", "gtin" => "789", "dataCriacao" => "2025-11-13 16:39:39", "dataAlteracao" => "2025-11-14 15:10:39",
      "precos" => { "preco" => price, "precoPromocional" => 0, "precoCusto" => 40.0, "precoCustoMedio" => 38.5 },
      "estoque" => { "localizacao" => "" }
    }
  end

  def stub_listing(path, items, total: items.size)
    stub_request(:get, "#{base}#{path}").with(query: hash_including({ "limit" => "100", "offset" => "0" }))
      .to_return(status: 200, body: { itens: items, paginacao: { total: total, limit: 100, offset: 0 } }.to_json)
  end

  let(:stock_item) do
    { "idProduto" => 1, "sku" => "A", "saldo" => 7.0, "reservado" => 2.0, "disponivel" => 5.0, "localizacao" => "A1",
      "depositos" => [ { "id" => 9, "nome" => "Geral", "saldo" => 7.0 } ] }
  end

  it "guarda produtos com preços, custo e estoque, e fecha a rodada como success" do
    stub_listing("/produtos", [ product_item(1, sku: "A"), product_item(2, sku: "B", price: 55.5) ])
    stub_listing("/estoque", [ stock_item ])

    described_class.new(connection, run).call

    a = OlistProduct.find_by(company: company, olist_id: 1)
    expect(a).to have_attributes(sku: "A", price: 100, cost_price: 40, avg_cost_price: 38.5, stock_balance: 7,
      stock_reserved: 2, stock_available: 5, stock_location: "A1", status: "A")
    expect(a.stock_deposits.first).to include("nome" => "Geral")
    expect(a.olist_updated_at).to eq(Time.find_zone("America/Sao_Paulo").parse("2025-11-14 15:10:39"))
    expect(OlistProduct.find_by(olist_id: 2).stock_balance).to be_nil
    expect(run.reload).to have_attributes(status: "success", products_count: 2, error: nil)
  end

  it "atualiza o que já existe, sem duplicar, e remove o que sumiu do Olist" do
    create(:olist_product, company: company, olist_id: 1, price: 1, synced_at: 1.day.ago)
    create(:olist_product, company: company, olist_id: 99, synced_at: 1.day.ago)
    stub_listing("/produtos", [ product_item(1, sku: "A", price: 120.0) ])
    stub_listing("/estoque", [])

    described_class.new(connection, run).call

    expect(OlistProduct.where(company: company).pluck(:olist_id)).to eq([ 1 ])
    expect(OlistProduct.find_by(olist_id: 1).price).to eq(120)
  end

  it "não mexe nos produtos de outra empresa" do
    other = create(:olist_product)
    stub_listing("/produtos", [ product_item(1, sku: "A") ])
    stub_listing("/estoque", [])

    described_class.new(connection, run).call

    expect(OlistProduct.exists?(other.id)).to be true
  end

  it "percorre várias páginas" do
    first = (1..100).map { |i| product_item(i, sku: "S#{i}") }
    stub_request(:get, "#{base}/produtos").with(query: hash_including({ "offset" => "0" }))
      .to_return(status: 200, body: { itens: first, paginacao: { total: 101 } }.to_json)
    stub_request(:get, "#{base}/produtos").with(query: hash_including({ "offset" => "100" }))
      .to_return(status: 200, body: { itens: [ product_item(101, sku: "S101") ], paginacao: { total: 101 } }.to_json)
    stub_listing("/estoque", [])

    described_class.new(connection, run).call

    expect(OlistProduct.where(company: company).count).to eq(101)
  end

  it "falha no Olist: marca a rodada como failed e não apaga nada do que já estava guardado" do
    keep = create(:olist_product, company: company, synced_at: 1.day.ago)
    stub_listing("/produtos", [ product_item(1, sku: "A") ])
    stub_request(:get, "#{base}/estoque").with(query: hash_including({})).to_return(status: 500, body: "erro")
    allow_any_instance_of(Olist::Client).to receive(:sleep)

    described_class.new(connection, run).call

    expect(run.reload).to have_attributes(status: "failed", error: "Não foi possível consultar o Olist agora.")
    expect(OlistProduct.exists?(keep.id)).to be true
    expect(OlistProduct.where(company: company).count).to eq(1)
  end

  describe ".start_run" do
    it "reaproveita a rodada em andamento" do
      first, created = described_class.start_run(connection, trigger: "auto")
      second, created_again = described_class.start_run(connection, trigger: "manual")

      expect([ created, created_again ]).to eq([ true, false ])
      expect(second.id).to eq(first.id)
    end

    it "uma rodada travada há mais de 10 min é encerrada e não bloqueia a nova" do
      stuck = create(:olist_sync_run, company: company, started_at: 11.minutes.ago)

      fresh, created = described_class.start_run(connection, trigger: "auto")

      expect(created).to be true
      expect(fresh.id).not_to eq(stuck.id)
      expect(stuck.reload).to have_attributes(status: "failed", error: OlistSyncRun::STALE_ERROR)
    end
  end
end
