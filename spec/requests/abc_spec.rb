require "rails_helper"

RSpec.describe "Curva ABC (/api/abc)", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  let!(:metric_a) do
    create(:item_metric, ml_account: account, item_id: "MLB1", title: "Item A", status: "active", sku: "SKU-A",
      listing_type: "P", full: false, free_shipping: true, price: 100.0, stock: 10, quality_score: 85,
      visits_30d: 200, prev_visits_30d: 180, units_30d: 20, prev_units_30d: 10,
      revenue_30d: 2000.0, prev_revenue_30d: 1000.0, fees_30d: 200.0, conversion_30d: 10.0, prev_conversion_30d: 5.5)
  end

  let!(:metric_b) do
    create(:item_metric, ml_account: account, item_id: "MLB2", title: "Item B", status: "active", sku: "SKU-B",
      listing_type: "C", full: false, free_shipping: false, price: 50.0, stock: 5, quality_score: 60,
      visits_30d: 50, prev_visits_30d: 60, units_30d: 2, prev_units_30d: 5,
      revenue_30d: 100.0, prev_revenue_30d: 250.0, fees_30d: 10.0, conversion_30d: 4.0, prev_conversion_30d: 8.0)
  end

  before do
    create(:ml_item, ml_account: account, item_id: "MLB1", price: 100.0, fee_now: 10.0, ship_cost: 5.0)
    create(:ml_item, ml_account: account, item_id: "MLB2", price: 50.0, fee_now: 5.0, ship_cost: 3.0)
  end

  describe "GET /api/abc" do
    it "devolve o formato exato da SPEC 10.5" do
      get "/api/abc", params: { account_id: account.id }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)

      expect(numeric_strings(json)).to be_empty
      expect(json.keys).to contain_exactly("params", "period", "has_costs", "details", "notice", "summary", "groups", "rows")
      expect(json["params"].keys).to contain_exactly("tax_pct", "min_margin_pct", "cut_a", "cut_b", "up_pct", "down_pct")

      row = json["rows"].find { |r| r["id"] == "MLB1" }
      expect(row.keys).to contain_exactly(
        "id", "title", "status_label", "sku", "full", "curve", "group", "rank", "share_pct", "cum_pct",
        "visits_30d", "units_30d", "units_change_pct", "units_change_state", "is_new", "conversion_30d",
        "revenue_30d", "profit_month", "profit_is_before_cost", "margin_pct", "margin_state",
        "suggestions_count", "urgent_count", "profit_state"
      )
    end

    it "curve=A filtra as linhas mas mantém o summary com as três curvas" do
      get "/api/abc", params: { account_id: account.id, curve: "A" }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json["rows"].size).to eq(1)
      expect(json["rows"]).to all(include("curve" => "A"))
      expect(json["summary"].map { |s| s["curve"] }).to contain_exactly("A", "B", "C")
    end

    it "curva inválida cai pra all" do
      get "/api/abc", params: { account_id: account.id, curve: "Z" }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json["rows"].size).to eq(2)
    end

    it "conta de outra empresa -> 404" do
      other_account = create(:ml_account)

      get "/api/abc", params: { account_id: other_account.id }, headers: auth_headers(user)

      expect(response).to have_http_status(:not_found)
    end

    it "devolve 401 sem token" do
      get "/api/abc", params: { account_id: account.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/abc/items/:id" do
    it "devolve o formato exato da SPEC 10.6" do
      get "/api/abc/items/MLB1", params: { account_id: account.id }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)

      expect(numeric_strings(json)).to be_empty
      expect(json.keys).to contain_exactly("indicators", "month", "unit", "listing", "price", "suggestions", "links")
      expect(json["links"]["public"]).to eq("https://produto.mercadolivre.com.br/MLB-1")
    end

    it "anúncio fora do universo (closed sem faturamento) ainda responde detalhe, com curva nil" do
      create(:item_metric, ml_account: account, item_id: "MLB3", title: "Item C", status: "closed", sku: nil,
        price: 30.0, stock: 0, revenue_30d: 0, prev_revenue_30d: 0, units_30d: 0, prev_units_30d: 0, visits_30d: 0)
      create(:ml_item, ml_account: account, item_id: "MLB3", status: "closed", price: 30.0)

      get "/api/abc/items/MLB3", params: { account_id: account.id }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json["indicators"]["share_pct"]).to be_nil
      expect(json["indicators"]["cum_pct"]).to be_nil
    end

    it "conta de outra empresa -> 404" do
      other_user = create(:user)

      get "/api/abc/items/MLB1", params: { account_id: account.id }, headers: auth_headers(other_user)

      expect(response).to have_http_status(:not_found)
    end

    it "anúncio inexistente -> 404" do
      get "/api/abc/items/MLB999", params: { account_id: account.id }, headers: auth_headers(user)

      expect(response).to have_http_status(:not_found)
    end
  end
end
