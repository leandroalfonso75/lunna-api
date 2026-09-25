require "rails_helper"

RSpec.describe "/api/painel", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  it "devolve o snapshot completo (SPEC 10.3)" do
    create(:ml_item, ml_account: account, item_id: "MLB1", status: "active")
    create(:item_metric, ml_account: account, item_id: "MLB1", status: "active", units_7d: 3, visits_7d: 10)
    create(:ml_sync_run, ml_account: account, ok: true, started_at: 5.minutes.ago, finished_at: 5.minutes.ago)

    get "/api/painel", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)

    expect(numeric_strings(json)).to be_empty
    expect(json["account"]).to eq("id" => account.id, "nickname" => account.nickname, "seller_id" => account.seller_id)
    expect(json["sync"]["state"]).to eq("ok")
    expect(json["kpis"].size).to eq(6)
    expect(json["daily"].size).to eq(15)
    expect(json).to have_key("daily_scale")
    expect(json).to have_key("top_sellers")
    expect(json).to have_key("recent_sales")
    expect(json["summary"]).to include("total" => 1, "active" => 1)
    expect(json["alerts"]).to all(satisfy { |alert| !alert.key?("item_ids") })
    expect(json["period"].keys).to match_array(%w[today week prev_week month prev_month])
  end

  it "conta de outra empresa devolve 404" do
    other_account = create(:ml_account)

    get "/api/painel", params: { account_id: other_account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:not_found)
  end

  it "sem account_id devolve 422" do
    get "/api/painel", headers: auth_headers(member)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "sem token devolve 401" do
    get "/api/painel", params: { account_id: account.id }

    expect(response).to have_http_status(:unauthorized)
  end
end
