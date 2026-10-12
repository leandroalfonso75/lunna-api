require "rails_helper"

RSpec.describe Olist::SyncProducts, "vínculo de variações" do
  let(:company) { create(:company) }
  let(:connection) { create(:olist_connection, company: company) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }
  let(:updated) { "2026-10-01 10:00:00" }

  def item(id, sku, kind, status: "A", updated: "2026-10-01 10:00:00")
    {
      "id" => id, "sku" => sku, "descricao" => "Produto #{sku}", "tipo" => "S", "situacao" => status, "tipoVariacao" => kind,
      "dataCriacao" => "2026-01-01 10:00:00", "dataAlteracao" => updated, "precos" => { "preco" => 10.0 }
    }
  end

  def stub_all(items, stock: [])
    stub_request(:get, "#{base}/produtos").with(query: hash_including({ "limit" => "100" }))
      .to_return(status: 200, body: { itens: items, paginacao: { total: items.size } }.to_json)
    stub_request(:get, "#{base}/estoque").with(query: hash_including({ "limit" => "100" }))
      .to_return(status: 200, body: { itens: stock, paginacao: { total: stock.size } }.to_json)
  end

  def stub_parent(id, variation_ids)
    stub_request(:get, "#{base}/produtos/#{id}")
      .to_return(status: 200, body: { id: id, variacoes: variation_ids.map { |vid| { id: vid } } }.to_json)
  end

  def sync
    run, = described_class.start_run(connection, trigger: "manual")
    described_class.new(connection, run).call
    run
  end

  it "liga cada variação ao pai a partir da lista de variações do pai" do
    stub_all([ item(1, "PAI", "P"), item(2, "PAI-A", "V"), item(3, "PAI-B", "V"), item(4, "SOLTO", "N") ])
    stub_parent(1, [ 2, 3 ])

    sync

    expect(OlistProduct.where(company: company, variation_kind: "V").pluck(:parent_olist_id)).to eq([ 1, 1 ])
    expect(OlistProduct.find_by(olist_id: 4).parent_olist_id).to be_nil
    expect(OlistProduct.find_by(olist_id: 1).variation_ids).to contain_exactly(2, 3)
  end

  it "não relê o pai enquanto ele não mudou no Olist" do
    stub_all([ item(1, "PAI", "P"), item(2, "PAI-A", "V") ])
    stub_parent(1, [ 2 ])

    sync
    sync

    expect(WebMock).to have_requested(:get, "#{base}/produtos/1").once
    expect(OlistProduct.find_by(olist_id: 2).parent_olist_id).to eq(1)
  end

  it "relê o pai quando ele foi alterado (variação nova)" do
    stub_all([ item(1, "PAI", "P"), item(2, "PAI-A", "V") ])
    stub_parent(1, [ 2 ])
    sync

    stub_all([ item(1, "PAI", "P", updated: "2026-10-05 09:00:00"), item(2, "PAI-A", "V"), item(5, "PAI-C", "V") ])
    stub_parent(1, [ 2, 5 ])
    sync

    expect(WebMock).to have_requested(:get, "#{base}/produtos/1").twice
    expect(OlistProduct.find_by(olist_id: 5).parent_olist_id).to eq(1)
  end

  it "variação removida do pai deixa de apontar para ele" do
    stub_all([ item(1, "PAI", "P"), item(2, "PAI-A", "V"), item(3, "PAI-B", "V") ])
    stub_parent(1, [ 2, 3 ])
    sync

    stub_all([ item(1, "PAI", "P", updated: "2026-10-05 09:00:00"), item(2, "PAI-A", "V"), item(3, "PAI-B", "V") ])
    stub_parent(1, [ 2 ])
    sync

    expect(OlistProduct.find_by(olist_id: 3).parent_olist_id).to be_nil
  end

  it "variação excluída sem pai é normal e não faz reler os outros pais" do
    stub_all([ item(1, "PAI", "P"), item(2, "PAI-A", "V"), item(9, "ORFA", "V", status: "E") ])
    stub_parent(1, [ 2 ])

    sync
    sync

    expect(WebMock).to have_requested(:get, "#{base}/produtos/1").once
    expect(OlistProduct.find_by(olist_id: 9).parent_olist_id).to be_nil
  end

  it "variação ativa sem pai conhecido faz reler os demais pais" do
    stub_all([ item(1, "PAI", "P"), item(2, "PAI-A", "V"), item(8, "PAI2", "P"), item(9, "SEM-PAI", "V") ])
    stub_parent(1, [ 2 ])
    stub_parent(8, [ 9 ])
    sync

    # Segunda rodada: pai 8 muda de lista sem mudar a data; o vínculo continua pelo cache.
    expect(OlistProduct.find_by(olist_id: 9).parent_olist_id).to eq(8)
  end

  it "falha ao ler um pai não derruba a sincronização e mantém o vínculo anterior" do
    stub_all([ item(1, "PAI", "P"), item(2, "PAI-A", "V") ])
    stub_parent(1, [ 2 ])
    sync

    stub_all([ item(1, "PAI", "P", updated: "2026-10-05 09:00:00"), item(2, "PAI-A", "V") ])
    stub_request(:get, "#{base}/produtos/1").to_return(status: 500, body: "erro")
    allow_any_instance_of(Olist::Client).to receive(:sleep)

    run = sync

    expect(run.reload.status).to eq("success")
    expect(OlistProduct.find_by(olist_id: 2).parent_olist_id).to eq(1)
  end
end
