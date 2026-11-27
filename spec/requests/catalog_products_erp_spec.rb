require "rails_helper"

# Ficha completa vinda do ERP (migração de 27/11/2026).
RSpec.describe "/api/catalog_products (fichas do ERP)", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }

  before do
    OlistProduct.create!(company: company, olist_id: 1, sku: "PAI", description: "Pai", kind: "V", status: "A", synced_at: Time.current)
    OlistProduct.create!(company: company, olist_id: 2, sku: "FILHO", description: "Filho", kind: "S", status: "A", parent_olist_id: 1,
                         stock_available: 4, fifo_unit_cost: 12.5, synced_at: Time.current)
    company.catalog_products.create!(kind: "variations", source: "erp", erp_key: "olist", erp_id: 1, name: "Pai", sku: "PAI", status: "pronto",
                                     variation_axes: [ "Cor" ], variations: [ { "key" => "erp-2", "erp_id" => 2, "sku" => "FILHO", "attrs" => { "Cor" => "Azul" } } ])
    company.catalog_products.create!(kind: "simple", name: "Criado no Lunna")
  end

  it "a lista padrão mostra só os criados no Lunna; ?source=erp mostra os do ERP" do
    get "/api/catalog_products", headers: auth_headers(user)
    expect(json["products"].map { |p| p["name"] }).to eq([ "Criado no Lunna" ])
    get "/api/catalog_products", params: { source: "erp" }, headers: auth_headers(user)
    expect(json["products"].map { |p| p["name"] }).to eq([ "Pai" ])
  end

  it "abre a ficha pelo id do ERP (a variação abre o pai), com estoque e custo PEPS da cópia sincronizada" do
    get "/api/catalog_products/erp/2", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json).to include("erp_id" => 1, "source" => "erp", "erp_name" => "Olist")
    expect(json["erp_stock"]["variations"]["erp-2"]).to include("stock" => 4.0, "cost" => 12.5)
  end

  it "produto ainda não importado responde 404 com a explicação" do
    get "/api/catalog_products/erp/999", headers: auth_headers(user)
    expect(response).to have_http_status(:not_found)
    expect(json["errors"].first).to include("ainda não foi importado")
  end

  it "Reimportar do ERP: só administrador, relê a ficha pelo id do ERP" do
    product = company.catalog_products.find_by(erp_id: 1)
    allow(Erp::CatalogImport).to receive(:call).and_return(Erp::CatalogImport::Result.new(imported: [ { erp_id: 1 } ], skipped: [], errors: []))

    post "/api/catalog_products/#{product.id}/reimport", headers: auth_headers(user)
    expect(response).to have_http_status(:forbidden)

    admin = create(:user, :admin, company: company)
    post "/api/catalog_products/#{product.id}/reimport", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(Erp::CatalogImport).to have_received(:call).with(company, erp_ids: [ 1 ])
  end
end
