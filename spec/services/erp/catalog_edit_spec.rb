require "rails_helper"

# Edição da ficha vinda do ERP (28/11/2026): "Salvar apenas no Lunna" e "Salvar no Lunna e ERP" (ERP simulado).
RSpec.describe Erp::CatalogEdit do
  let(:company) { create(:company) }
  let!(:connection) { create(:olist_connection, company: company) }
  let(:user) { create(:user, :admin, company: company) }

  let(:fake_client) do
    Class.new do
      attr_reader :writes
      def initialize(base) = (@base = base) && (@writes = [])
      def product(id) = @base.fetch(id.to_i)
      def update_product(id, body) = (@writes << [ :product, id, body ]) && {}
      def update_variation(id, vid, body) = (@writes << [ :variation, id, vid, body ]) && {}
      def update_kit(id, items) = (@writes << [ :kit, id, items ]) && {}
    end
  end
  let(:erp_base) do
    { "id" => 10, "sku" => "ESC", "descricao" => "Escova", "tipo" => "S", "situacao" => "A", "unidade" => "UN", "ncm" => "8516.32.00",
      "marca" => { "id" => 5, "nome" => "Gama" }, "categoria" => { "id" => 7, "nome" => "Escovas" },
      "precos" => { "preco" => 296.91, "precoPromocional" => 0, "precoCusto" => 99.5 },
      "estoque" => { "controlar" => true, "quantidade" => 76, "minimo" => 0, "maximo" => 0, "localizacao" => "", "diasPreparacao" => 0 },
      "dimensoes" => { "embalagem" => { "id" => nil, "tipo" => 2, "descricao" => "" }, "largura" => 0, "altura" => 0, "comprimento" => 0, "pesoLiquido" => 0, "pesoBruto" => 0 },
      "seo" => { "titulo" => "", "descricao" => "", "keywords" => [], "linkVideo" => "", "slug" => "escova" },
      "fornecedores" => [ { "id" => 0, "nome" => "" } ], "anexos" => [ { "url" => "https://img/1.jpg" } ], "custos" => [ { "precoCusto" => 99.5 } ] }
  end

  let(:product) do
    company.catalog_products.create!(kind: "simple", source: "erp", erp_key: "olist", erp_id: 10, name: "Escova", sku: "ESC", price: 296.91,
                                     ncm: "85163200", brand: "Gama", status: "pronto")
  end

  def edit(params, mode:, client: fake_client.new(10 => erp_base), dry_run: false)
    writer = Erp::OlistProductWriter.new(company, user: user, client: client)
    described_class.new(company, user: user, writer: writer).call(product, params, mode: mode, dry_run: dry_run)
  end

  it "prévia: diz o que muda e o que não pode ir ao ERP, sem gravar nada" do
    r = edit({ fields: { price: "289,90", brand: "Outra", name: "Escova Nova" } }, mode: "erp", dry_run: true)

    expect(r.changes.map { |c| [ c[:key], c[:erp] ] }).to contain_exactly([ "price", true ], [ "brand", false ], [ "name", true ])
    expect(r.changes.find { |c| c[:key] == "brand" }[:reason]).to include("código")
    expect(product.reload.price.to_f).to eq(296.91)
  end

  it "salvar apenas no Lunna: grava, marca o campo como ajustado com o valor do ERP e a reimportação não sobrescreve" do
    client = fake_client.new(10 => erp_base)
    edit({ fields: { price: "289.90" } }, mode: "lunna", client: client)

    expect(client.writes).to be_empty
    expect(product.reload.price.to_f).to eq(289.9)
    expect(product.local_overrides["price"]).to include("erp_value" => "296.91")

    # a reimportação (o ERP ainda com 296,91) mantém o ajuste do Lunna
    payload = erp_base.merge("anexos" => [])
    Erp::CatalogImport.call(company, erp_ids: [ 10 ], client: fake_client.new(10 => payload), downloader: ->(_) { nil })
    expect(product.reload.price.to_f).to eq(289.9)
    expect(product.local_overrides["price"]["erp_value"]).to eq(296.91)

    # voltar ao valor do ERP
    described_class.new(company, user: user).reset!(product, "price")
    expect(product.reload.price.to_f).to eq(296.91)
    expect(product.local_overrides).not_to have_key("price")
  end

  it "salvar no Lunna e ERP: relê o ERP, manda o objeto inteiro com só o que mudou, sem mexer no custo, e registra" do
    client = fake_client.new(10 => erp_base)
    r = edit({ fields: { price: "289.90", ncm: "85163100", keywords: "escova, rotativa" } }, mode: "erp", client: client)

    kind, id, body = client.writes.first
    expect([ kind, id ]).to eq([ :product, 10 ])
    expect(body["precos"]).to include("preco" => 289.9, "precoCusto" => 99.5) # custo como está no ERP (PEPS não muda)
    expect(body["ncm"]).to eq("8516.31.00")
    expect(body["seo"]).to include("keywords" => %w[escova rotativa], "slug" => "escova")
    expect(body["marca"]).to eq("id" => 5)
    expect(body).not_to have_key("anexos")
    expect(body["estoque"]).not_to have_key("quantidade")
    expect(r.erp[:results].first).to include(ok: true)
    expect(product.reload.local_overrides).to be_empty # o ERP aceitou: Lunna e ERP iguais
    expect(OlistChange.last).to have_attributes(kind: "product", status: "done", olist_product_id: 10)
  end

  it "se o ERP recusar, fica salvo no Lunna como ajuste e o resultado diz o que não foi" do
    failing = fake_client.new(10 => erp_base)
    def failing.update_product(*) = raise(Olist::Client::Error.new(status: 403, path: "/produtos/10", body: "sem permissão"))

    r = edit({ fields: { price: "289.90" } }, mode: "erp", client: failing)

    expect(r.erp[:results].first).to include(ok: false)
    expect(product.reload.price.to_f).to eq(289.9)
    expect(product.local_overrides).to have_key("price")
    expect(OlistChange.last).to have_attributes(status: "failed")
  end

  it "variações: SKU/GTIN/preço vão ao ERP; o valor da variação (cor, tom) fica só no Lunna, com explicação" do
    product.update!(kind: "variations", variation_axes: [ "Tom" ],
                    variations: [ { "key" => "erp-11", "erp_id" => 11, "sku" => "ESC-1", "price" => 10, "attrs" => { "Tom" => "101" } } ])
    client = fake_client.new(10 => erp_base, 11 => erp_base.merge("id" => 11, "sku" => "ESC-1"))
    r = edit({ variations: { "erp-11" => { "price" => "12.5", "attrs" => { "Tom" => "102" } } } }, mode: "erp", client: client)

    expect(client.writes.map(&:first)).to eq([ :variation ])
    expect(client.writes.first[3]["precos"]["preco"]).to eq(12.5)
    expect(r.erp[:not_sent].map { |c| c[:label] }).to eq([ "Variação ESC-1 · Tom" ])
    expect(product.reload.variations.first).to include("price" => 12.5, "attrs" => { "Tom" => "102" })
    expect(product.local_overrides).to have_key("variations")
  end
end
