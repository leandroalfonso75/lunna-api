require "rails_helper"

RSpec.describe "Anúncios > Catálogo (/api/items/catalog)", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  before do
    create(:ml_item, ml_account: account, item_id: "MLB10", title: "Base Tradicional", status: "active", sku: "LS-BASE-01", price: 59.9)
    create(:ml_item, ml_account: account, item_id: "MLB1", title: "Base Catálogo", status: "active", catalog_listing: true, sku: "LS-BASE-01",
                     item_relations: [ { "id" => "MLB10" } ], catalog_status: "winning", catalog_checked_at: 1.hour.ago)
    create(:ml_item, ml_account: account, item_id: "MLB2", title: "Gloss Catálogo", status: "active", catalog_listing: true,
                     item_relations: [], catalog_status: "competing", catalog_price_to_win: 25.5, catalog_reasons: [ "price" ])
  end

  it "lista os de catálogo com sincronização, ganhando/perdendo e SKUs" do
    get "/api/items/catalog", params: { account_id: account.id }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json["counts"]).to include("total" => 2, "sincronizado" => 1, "nao_sincronizado" => 1, "ganhando" => 1, "perdendo" => 1)
    win = json["items"].find { |i| i["item_id"] == "MLB1" }
    expect(win).to include("sync" => "sincronizado", "state" => "ganhando", "skus" => [ "LS-BASE-01" ])
    expect(win["related"].first).to include("item_id" => "MLB10", "title" => "Base Tradicional")
    lose = json["items"].find { |i| i["item_id"] == "MLB2" }
    expect(lose).to include("sync" => "nao_sincronizado", "state" => "perdendo", "price_to_win" => 25.5, "reasons" => [ "preço" ])

    get "/api/items/catalog", params: { account_id: account.id, sync: "nao_sincronizado" }, headers: auth_headers(user)
    expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLB2" ])
  end
end
