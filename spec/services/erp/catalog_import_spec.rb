require "rails_helper"

# Migração dos produtos do ERP para a ficha completa do Lunna (27/11/2026).
RSpec.describe Erp::CatalogImport do
  let(:company) { create(:company) }
  let!(:connection) { create(:olist_connection, company: company) }

  def mirror(olist_id, sku, kind: "S", status: "A", parent: nil, available: 0, fifo: nil, hidden: nil)
    OlistProduct.create!(company: company, olist_id: olist_id, sku: sku, description: sku, kind: kind, status: status, parent_olist_id: parent,
                         stock_available: available, fifo_unit_cost: fifo, hidden_at: hidden, synced_at: Time.current)
  end

  def erp(id, sku, tipo: "S", **extra)
    { "id" => id, "sku" => sku, "descricao" => "Produto #{sku}", "tipo" => tipo, "tipoVariacao" => tipo == "V" ? "P" : "N", "unidade" => "UN",
      "ncm" => "8516.32.00", "gtin" => "", "origem" => "0", "garantia" => "6 meses", "descricaoComplementar" => "Descrição de #{sku}",
      "marca" => { "nome" => "Marca X" }, "categoria" => { "caminhoCompleto" => "Beleza -> Cabelo" },
      "dimensoes" => { "largura" => 20, "altura" => 10, "comprimento" => 5, "pesoLiquido" => 0.5, "pesoBruto" => 0.6 },
      "precos" => { "preco" => 100, "precoCusto" => 99 }, "estoque" => { "controlar" => true, "quantidade" => 7 },
      "anexos" => [ { "url" => "https://img.test/#{sku}-1.jpg" }, { "url" => "https://img.test/#{sku}-2.jpg" } ],
      "variacoes" => [], "kit" => [], "seo" => { "linkVideo" => "https://video.test/#{sku}" },
      "custos" => [ { "precoCusto" => 99 } ] }.merge(extra)
  end

  let(:client) do
    Class.new do
      attr_reader :calls
      def initialize(map) = (@map = map) && (@calls = [])
      def product(id) = (@calls << id) && @map.fetch(id.to_i)
    end
  end
  let(:jpeg) { "\xFF\xD8\xFF\xE0fake".b }
  let(:downloads) { [] }
  let(:downloader) { ->(url) { downloads << url; [ jpeg, "image/jpeg" ] } }

  it "simples: ficha presa ao id do ERP, com os dados do cadastro, fotos na ordem e custo PEPS intacto" do
    m = mirror(10, "ESC", available: 76, fifo: 149.9)
    payload = erp(10, "ESC")
    result = described_class.call(company, erp_ids: [ 10 ], client: client.new(10 => payload), downloader: downloader)

    p = company.catalog_products.find_by(erp_id: 10)
    expect(result.errors).to be_empty
    expect(p).to have_attributes(source: "erp", erp_key: "olist", kind: "simple", status: "pronto", sku: "ESC", ncm: "85163200",
                                 brand: "Marca X", category: "Beleza -> Cabelo", warranty: "6 meses", package_width: 20, package_source: "erp",
                                 video_url: "https://video.test/ESC", cost_price: nil)
    expect(p.erp_payload).not_to have_key("custos") # o histórico de custos do ERP não é copiado
    expect(p.assets.order(:position).map(&:source_url)).to eq(%w[https://img.test/ESC-1.jpg https://img.test/ESC-2.jpg])
    expect(m.reload.fifo_unit_cost.to_f).to eq(149.9) # PEPS da cópia sincronizada não muda
    expect(Erp::CatalogStock.call(company, p)).to include(stock: 76.0, cost: 149.9)

    # reimportar com as mesmas fotos não baixa de novo nem duplica
    described_class.call(company, erp_ids: [ 10 ], client: client.new(10 => payload), downloader: downloader)
    expect(company.catalog_products.where(erp_id: 10).count).to eq(1)
    expect(downloads.size).to eq(2)
  end

  it "com variações que são kits: eixos da grade, componentes, fotos próprias da variação e estoque do kit pelo componente que acaba primeiro" do
    mirror(1, "SEC", kind: "V")
    mirror(2, "SEC-110", kind: "K", parent: 1)
    mirror(3, "SEC-220", kind: "K", parent: 1)
    mirror(4, "SECADOR-110", available: 5, fifo: 100)
    mirror(5, "SECADOR-220", available: 12, fifo: 100)
    mirror(6, "DIF", available: 60, fifo: 10)
    var = ->(id, sku, volt) { { "id" => id, "sku" => sku, "gtin" => "", "tipo" => "K", "precos" => { "preco" => 280 }, "estoque" => { "quantidade" => 21 }, "grade" => [ { "chave" => "Voltagem", "valor" => volt } ] } }
    parent = erp(1, "SEC", tipo: "V", "variacoes" => [ var.(2, "SEC-110", "127v"), var.(3, "SEC-220", "220v") ])
    kit = ->(id, sku, comp, qty) { erp(id, sku, tipo: "K", "anexos" => [ { "url" => "https://img.test/SEC-1.jpg" }, { "url" => "https://img.test/#{sku}.jpg" } ],
                                         "kit" => [ { "produto" => { "id" => 4, "sku" => comp }, "quantidade" => qty }, { "produto" => { "id" => 6, "sku" => "DIF" }, "quantidade" => 1 } ]) }
    map = { 1 => parent, 2 => kit.(2, "SEC-110", "SECADOR-110", 1), 3 => kit.(3, "SEC-220", "SECADOR-220", 2) }

    # pedir a variação importa o pai
    described_class.call(company, erp_ids: [ 2 ], client: client.new(map), downloader: downloader)

    p = company.catalog_products.find_by(erp_id: 1)
    expect(p.kind).to eq("variations")
    expect(p.variation_axes).to eq([ "Voltagem" ])
    v110 = p.variations.find { |v| v["sku"] == "SEC-110" }
    expect(v110).to include("attrs" => { "Voltagem" => "127v" }, "kit" => true, "erp_id" => 2)
    expect(v110["components"]).to eq([ { "sku" => "SECADOR-110", "quantity" => 1.0 }, { "sku" => "DIF", "quantity" => 1.0 } ])
    # foto que repete a do pai não é duplicada; a própria fica presa à variação
    expect(p.assets.where(variation_key: "erp-2").map(&:source_url)).to eq([ "https://img.test/SEC-110.jpg" ])

    stock = Erp::CatalogStock.call(company, p)
    expect(stock[:variations]["erp-2"]).to include(stock: 5, cost: 110.0)    # 5 secadores, 60 difusores → 5 kits
    expect(stock[:variations]["erp-3"]).to include(stock: 6, cost: 210.0)    # 12 secadores ÷ 2 por kit → 6 kits
    expect(stock[:total_stock]).to eq(11.0)
  end

  it "não importa inativo/excluído no ERP nem o removido da lista do Lunna, e diz por quê" do
    mirror(20, "INATIVO", status: "E")
    mirror(21, "OCULTO", hidden: Time.current)
    result = described_class.call(company, erp_ids: [ 20, 21 ], client: client.new({}), downloader: downloader)

    expect(result.skipped.map { |s| s[:reason] }).to contain_exactly("inativo/excluído no ERP", "removido da lista do Lunna")
    expect(company.catalog_products.count).to eq(0)
  end

  it "o ERP manda: GTIN inválido e falta de dados viram avisos, não barram a cópia; componente inativo zera o kit" do
    mirror(30, "KIT", kind: "K")
    mirror(31, "COMP-INATIVO", status: "E", available: 50)
    payload = erp(30, "KIT", tipo: "K", "gtin" => "1234567890123", "ncm" => "", "dimensoes" => {}, "anexos" => [],
                  "kit" => [ { "produto" => { "id" => 31, "sku" => "COMP-INATIVO" }, "quantidade" => 1 } ])
    described_class.call(company, erp_ids: [ 30 ], client: client.new(30 => payload), downloader: downloader)

    p = company.catalog_products.find_by(erp_id: 30)
    expect(p.erp_warnings).to include("sem imagens no ERP", "sem NCM", "sem medidas da embalagem", "GTIN inválido (1234567890123)",
                                      "componente COMP-INATIVO não está ativo no ERP (o estoque do kit fica zero)")
    expect(Erp::CatalogStock.call(company, p)[:stock]).to eq(0)
  end
end
