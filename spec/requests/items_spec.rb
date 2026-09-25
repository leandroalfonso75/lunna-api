require "rails_helper"

RSpec.describe "/api/items", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  it "devolve a tabela filtrada e paginada (SPEC 10.4)" do
    create(:item_metric, ml_account: account, status: "active", title: "Produto A", units_7d: 5)
    create(:item_metric, ml_account: account, status: "paused", title: "Produto B")

    get "/api/items", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)

    expect(numeric_strings(json)).to be_empty
    expect(json["items"].size).to eq(1) # status ativo por padrão
    expect(json["items"].first["title"]).to eq("Produto A")
    expect(json).to include("total" => 1, "page" => 1, "per_page" => 50)
    expect(json["status_counts"]).to eq("active" => 1, "paused" => 1, "closed" => 0, "all" => 2)
    expect(json["sort"]).to eq("units_7d")
    expect(json["dir"]).to eq("desc")
  end

  it "aceita os filtros (status, q, type, f[]) como query params" do
    create(:item_metric, ml_account: account, status: "active", title: "Tênis Azul", listing_type: "P", price: 199.9)
    create(:item_metric, ml_account: account, status: "active", title: "Tênis Verde", listing_type: "C", price: 50)

    get "/api/items", params: { account_id: account.id, q: "Azul", type: "P", f: { price: ">100" } }, headers: auth_headers(member)

    expect(json["items"].map { |i| i["title"] }).to eq([ "Tênis Azul" ])
  end

  it "conta de outra empresa devolve 404" do
    other_account = create(:ml_account)

    get "/api/items", params: { account_id: other_account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:not_found)
  end

  it "sem account_id devolve 422" do
    get "/api/items", headers: auth_headers(member)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
