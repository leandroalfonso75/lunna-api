require "rails_helper"

# Editar a ficha vinda do ERP (28/11/2026). O ERP é simulado: nada é gravado de verdade.
RSpec.describe "/api/catalog_products/:id (edição das fichas do ERP)", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:user) { create(:user, company: company) }
  let!(:product) do
    company.catalog_products.create!(kind: "simple", source: "erp", erp_key: "olist", erp_id: 10, name: "Escova", sku: "ESC", price: 100, status: "pronto")
  end

  it "só administrador edita" do
    post "/api/catalog_products/#{product.id}/erp_edit", params: { fields: { price: "90" } }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "prévia (dry_run) não grava; salvar apenas no Lunna grava e marca o ajuste; voltar ao ERP desfaz" do
    post "/api/catalog_products/#{product.id}/erp_edit", params: { mode: "erp", dry_run: true, fields: { price: "90" } }, headers: auth_headers(admin), as: :json
    expect(json["changes"].first).to include("key" => "price", "erp" => true)
    expect(product.reload.price.to_f).to eq(100)

    post "/api/catalog_products/#{product.id}/erp_edit", params: { mode: "lunna", fields: { price: "90" } }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(json["product"]["price"].to_f).to eq(90)
    expect(json["product"]["local_overrides"]["price"]).to include("erp_value" => "100.0")
    expect(json["erp"]).to be_nil

    post "/api/catalog_products/#{product.id}/reset_override", params: { field: "price" }, headers: auth_headers(admin), as: :json
    expect(json["price"].to_f).to eq(100)
    expect(json["local_overrides"]).to eq({})
  end

  it "Salvar no Lunna e ERP chama o envio ao ERP (simulado) e devolve o resultado" do
    writer = instance_double(Erp::OlistProductWriter, call: [ { what: "produto", fields: [ "price" ], ok: true } ])
    allow(Erp::OlistProductWriter).to receive(:new).and_return(writer)

    post "/api/catalog_products/#{product.id}/erp_edit", params: { mode: "erp", fields: { price: "90" } }, headers: auth_headers(admin), as: :json

    expect(writer).to have_received(:call).with(anything, fields: [ "price" ], variations: {}, kits: {})
    expect(json["erp"]["results"].first).to include("ok" => true)
    expect(json["product"]["local_overrides"]).to eq({})
  end

  it "adiciona foto otimizada (fica do Lunna, não do ERP)" do
    png = Base64.strict_encode64(File.binread(Rails.root.join("spec/fixtures/files/pixel.png"))) rescue nil
    png ||= "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    post "/api/catalog_products/#{product.id}/photos", params: { data: "data:image/png;base64,#{png}", name: "nova.png" }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:created)
    expect(json).to include("kind" => "foto", "from_erp" => false)
    expect(product.assets.count).to eq(1)
  end
end
