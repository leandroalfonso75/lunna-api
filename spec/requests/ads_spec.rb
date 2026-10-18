require "rails_helper"

RSpec.describe "/api/ads", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company) }

  def campaign(id, name: "Camp #{id}", status: "active", acos_target: 10.0)
    MlAdCampaign.create!(ml_account_id: account.id, campaign_id: id, name: name, status: status, strategy: "PROFITABILITY",
      acos_target: acos_target, daily_budget: 50)
  end

  def day(campaign_id, date, cost:, amount:, clicks: 10, prints: 1000, units: 1)
    MlAdDailyMetric.create!(ml_account_id: account.id, campaign_id: campaign_id, date: date, cost: cost, total_amount: amount,
      clicks: clicks, prints: prints, units: units)
  end

  def ad(item_id, campaign_id, metrics, title: "Produto #{item_id}", status: "active")
    MlAdItem.create!(ml_account_id: account.id, item_id: item_id, campaign_id: campaign_id, title: title, status: status, price: 50,
      metrics: { "30d" => metrics, "7d" => metrics, "90d" => metrics }, synced_at: Time.current)
  end

  it "resumo, campanhas e série diária, com as métricas recalculadas (ACOS, ROAS, CTR, CPC, conversão)" do
    campaign(1)
    campaign(2, acos_target: 5.0)
    day(1, Date.current - 1, cost: 10, amount: 200, clicks: 50, prints: 5000, units: 4)
    day(2, Date.current - 2, cost: 30, amount: 300, clicks: 50, prints: 5000, units: 6)

    get "/api/ads", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(numeric_strings(json)).to be_empty
    expect(json["summary"]).to include("cost" => 40.0, "total_amount" => 500.0, "acos" => 8.0, "roas" => 12.5, "clicks" => 100,
      "prints" => 10_000, "ctr" => 1.0, "cpc" => 0.4, "cvr" => 10.0, "units" => 10)
    by_name = json["campaigns"].to_h { |c| [ c["name"], c ] }
    expect(by_name["Camp 1"]).to include("acos_state" => "ok")        # ACOS 5 ≤ meta 10
    expect(by_name["Camp 2"]).to include("acos_state" => "bad")       # ACOS 10 > meta 5 × 1,2
    expect(json["daily"].size).to eq(30)
    expect(json["daily"].sum { |d| d["cost"] }).to eq(40.0)
  end

  it "período muda o recorte e compara com o período anterior quando há dados" do
    campaign(1)
    day(1, Date.current - 2, cost: 10, amount: 100)
    day(1, Date.current - 20, cost: 50, amount: 100)
    day(1, Date.current - 40, cost: 7, amount: 100)

    get "/api/ads", params: { account_id: account.id, period: "7d" }, headers: auth_headers(member)
    expect(json["summary"]["cost"]).to eq(10.0)

    get "/api/ads", params: { account_id: account.id, period: "30d" }, headers: auth_headers(member)
    expect(json["summary"]["cost"]).to eq(60.0)
    expect(json["previous"]["cost"]).to eq(7.0)
  end

  it "campanha sem venda fica com ACOS nulo, sem dividir por zero" do
    campaign(1)
    day(1, Date.current - 1, cost: 10, amount: 0, clicks: 0, units: 0)

    get "/api/ads", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["summary"]).to include("acos" => nil, "cvr" => nil, "cpc" => nil)
    expect(json["campaigns"].first["acos_state"]).to eq("bad")
  end

  it "lista de anúncios: filtros, busca, ordenação, sinais e totais" do
    campaign(1, acos_target: 10.0)
    campaign(2, status: "paused")
    ad("MLB1", 1, { "cost" => 100.0, "total_amount" => 2000.0, "units_quantity" => 20, "clicks" => 100, "prints" => 1000 }, title: "Batom Rosa")
    ad("MLB2", 1, { "cost" => 50.0, "total_amount" => 0.0, "units_quantity" => 0, "clicks" => 40, "prints" => 900 }, title: "Gloss")
    ad("MLB3", 1, { "cost" => 30.0, "total_amount" => 150.0, "units_quantity" => 2, "clicks" => 30, "prints" => 500 }, title: "Base")
    ad("MLB4", 2, { "cost" => 0.0 }, title: "Rímel", status: "paused")

    get "/api/ads/items", params: { account_id: account.id, sort: "cost" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq(%w[MLB1 MLB2 MLB3 MLB4])
    expect(json["totals"]).to include("cost" => 180.0, "total_amount" => 2150.0)
    expect(json["flags"]).to include("sem_venda" => 1, "bom" => 1, "acos_alto" => 1)
    first = json["items"].first
    expect(first["flag"]).to include("key" => "bom")
    expect(first["metrics"]).to include("acos" => 5.0, "roas" => 20.0)

    get "/api/ads/items", params: { account_id: account.id, campaign_id: 2 }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLB4" ])

    get "/api/ads/items", params: { account_id: account.id, q: "gloss" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLB2" ])

    get "/api/ads/items", params: { account_id: account.id, flag: "sem_venda" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLB2" ])

    get "/api/ads/items", params: { account_id: account.id, sort: "acos", dir: "asc" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }.first(2)).to eq(%w[MLB1 MLB3]) # sem ACOS vai para o fim
  end

  it "anúncio de campanha que não existe mais aparece como encerrada" do
    ad("MLB9", 999, { "cost" => 1.0 })

    get "/api/ads/items", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["items"].first["campaign"]).to include("name" => "Campanha encerrada")
  end

  it "conta de outra empresa é 404 e exige login" do
    other = create(:ml_account)
    get "/api/ads", params: { account_id: other.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:not_found)

    get "/api/ads", params: { account_id: account.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it "só administrador pede a leitura de novo (job na fila)" do
    post "/api/ads/sync", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    expect do
      post "/api/ads/sync", params: { account_id: account.id }, headers: auth_headers(admin)
    end.to have_enqueued_job(Ml::AdsSyncJob).with(account.id)
    expect(response).to have_http_status(:accepted)
  end
end
