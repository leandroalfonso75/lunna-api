require "rails_helper"

RSpec.describe "Produtos do Olist agrupados por pai", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }

  let!(:parent) do
    create(:olist_product, company: company, olist_id: 100, sku: "PAI", description: "Secador Pai", variation_kind: "P", kind: "V",
      stock_available: nil, stock_balance: nil, stock_reserved: nil, price: 200)
  end
  let!(:var_a) do
    create(:olist_product, company: company, olist_id: 101, sku: "PAI-110", description: "Secador 110v", variation_kind: "V",
      parent_olist_id: 100, stock_available: 10, stock_balance: 12, stock_reserved: 2)
  end
  let!(:var_b) do
    create(:olist_product, company: company, olist_id: 102, sku: "PAI-220", description: "Secador 220v", variation_kind: "V",
      parent_olist_id: 100, stock_available: 5, stock_balance: 5, stock_reserved: 0)
  end
  let!(:normal) { create(:olist_product, company: company, olist_id: 200, sku: "NORMAL", description: "Batom", variation_kind: "N") }

  def listed_ids = json["products"].map { |p| p["id"] }

  it "lista só pais e produtos normais; as variações vêm dentro do pai" do
    get "/api/olist/products", headers: auth_headers(member)

    expect(listed_ids).to contain_exactly(100, 200)
    expect(json["total"]).to eq(2)
    pai = json["products"].find { |p| p["id"] == 100 }
    expect(pai["variations_count"]).to eq(2)
    expect(pai["variations"].map { |v| v["sku"] }).to eq(%w[PAI-110 PAI-220])
    expect(pai["variations"].first["parent_id"]).to eq(100)
    expect(json["products"].find { |p| p["id"] == 200 }).to include("variations_count" => 0, "variations" => [])
  end

  it "o pai mostra o estoque somado das variações" do
    get "/api/olist/products", headers: auth_headers(member)

    stock = json["products"].find { |p| p["id"] == 100 }["stock"]
    expect(stock["available"].to_f).to eq(15.0)
    expect(stock["balance"].to_f).to eq(17.0)
    expect(stock["reserved"].to_f).to eq(2.0)
    expect(stock["total_available"].to_f).to eq(15.0)
  end

  it "soma o Full das variações no pai e no total" do
    account = create(:ml_account, company: company)
    [ [ var_a, 4 ], [ var_b, 6 ] ].each do |product, full|
      create(:ml_item, ml_account: account, sku: product.sku, logistic_type: "fulfillment", status: "active",
        inventory_refs: [ { "sku" => product.sku, "inventory_id" => "INV-#{product.olist_id}" } ])
      MlFullStock.create!(ml_account: account, inventory_id: "INV-#{product.olist_id}", available_units: full, total_units: full, synced_at: Time.current)
    end

    get "/api/olist/products", headers: auth_headers(member)

    pai = json["products"].find { |p| p["id"] == 100 }
    expect(pai["stock"]["full"]).to include("linked" => true, "available" => 10, "listings" => 2)
    expect(pai["stock"]["total_available"].to_f).to eq(25.0)
    expect(pai["variations"].first["stock"]["total_available"].to_f).to eq(14.0)
  end

  it "a busca por SKU de uma variação devolve o pai com todas as variações" do
    get "/api/olist/products", params: { q: "PAI-220" }, headers: auth_headers(member)

    expect(listed_ids).to eq([ 100 ])
    expect(json["products"].first["variations_count"]).to eq(2)
    expect(json["total"]).to eq(1)
  end

  it "a busca pelo nome do pai também acha" do
    get "/api/olist/products", params: { q: "secador pai" }, headers: auth_headers(member)

    expect(listed_ids).to eq([ 100 ])
  end

  it "o filtro de situação vale para o produto de cima" do
    parent.update!(status: "I")

    get "/api/olist/products", params: { status: "I" }, headers: auth_headers(member)

    expect(listed_ids).to eq([ 100 ])
  end

  it "variação cujo pai não existe aparece sozinha na lista" do
    orphan = create(:olist_product, company: company, olist_id: 300, sku: "ORFA", variation_kind: "V", parent_olist_id: nil, status: "E")
    ghost = create(:olist_product, company: company, olist_id: 301, sku: "FANTASMA", variation_kind: "V", parent_olist_id: 999_999)

    get "/api/olist/products", headers: auth_headers(member)

    expect(listed_ids).to include(orphan.olist_id, ghost.olist_id)
  end

  it "não mistura variações de outra empresa" do
    other = create(:olist_product, olist_id: 100, variation_kind: "P")
    create(:olist_product, company: other.company, olist_id: 500, variation_kind: "V", parent_olist_id: 100)

    get "/api/olist/products", headers: auth_headers(member)

    pai = json["products"].find { |p| p["id"] == 100 }
    expect(pai["variations_count"]).to eq(2)
  end

  it "o detalhe de um pai traz as variações; o de uma variação, não" do
    get "/api/olist/products/100", headers: auth_headers(member)
    expect(json["product"]["variations_count"]).to eq(2)

    get "/api/olist/products/101", headers: auth_headers(member)
    expect(json["product"]).to include("variations_count" => 0, "parent_id" => 100)
  end
end
