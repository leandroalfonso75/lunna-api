require "rails_helper"

# Anúncios vinculados a um produto, por canal (28/11/2026).
RSpec.describe Catalog::ChannelListings do
  let(:company) { create(:company) }
  let(:product) do
    company.catalog_products.create!(kind: "variations", source: "erp", erp_key: "olist", erp_id: 1, name: "Base", sku: "BASE", status: "pronto",
                                     variation_axes: [ "Tom" ],
                                     variations: [ { "key" => "a", "sku" => "BASE-1", "attrs" => { "Tom" => "1" } }, { "key" => "b", "sku" => "BASE-2", "attrs" => { "Tom" => "2" } } ])
  end

  it "sem conta do canal: o canal aparece como não conectado e sem anúncios" do
    ch = described_class.call(company, product).first
    expect(ch).to include(key: "mercado_livre", connected: false, listings: [])
  end

  it "anúncio com variações aparece uma vez só (o pai), com os SKUs ligados; ativos antes dos pausados" do
    account = create(:ml_account, company: company)
    pai = create(:ml_item, ml_account: account, item_id: "MLB1", sku: nil, status: "paused", title: "Base pai")
    outro = create(:ml_item, ml_account: account, item_id: "MLB2", sku: "BASE", status: "active", title: "Base simples")
    create(:ml_item, ml_account: account, item_id: "MLB3", sku: "OUTRO")
    MlOrder.create!(order_id: 9, ml_account_id: account.id)
    MlOrderItem.create!(order_id: 9, item_id: pai.item_id, sku: "BASE-1")
    MlOrder.create!(order_id: 10, ml_account_id: account.id)
    MlOrderItem.create!(order_id: 10, item_id: pai.item_id, sku: "BASE-2")

    listings = described_class.call(company, product).first[:listings]

    expect(listings.map { |l| l[:id] }).to eq([ outro.item_id, pai.item_id ])
    expect(listings.last).to include(skus: %w[BASE-1 BASE-2], status_label: "Pausado")
  end
end
