require "rails_helper"

RSpec.describe "/api/promotions", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 5, min_margin_pct: 9) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company) }
  let!(:item) { create(:ml_item, ml_account: account, sku: "SKU-A", price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }
  let!(:sibling) { create(:ml_item, ml_account: account, sku: "SKU-A", price: 100) }
  let(:fees) { { "price" => 95, "sale_fee" => 9.5, "percentage_fee" => 10, "fixed_fee" => 0 } }

  before do
    create(:olist_product, company: company, sku: "SKU-A", cost_price: 40, status: "A", kind: "S")
    MlPromotion.create!(ml_account: account, promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN", name: "Campanha 20%", status: "started")
    MlPromotionOffer.create!(ml_account: account, item_id: item.item_id, promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN",
      name: "Campanha 20%", status: "started", price: 80, original_price: 100, min_price: 50, max_price: 95, fees: fees)
    MlPromotionOffer.create!(ml_account: account, item_id: item.item_id, promotion_id: "P-2", promotion_type: "DEAL",
      name: "Evento", status: "candidate", original_price: 100, min_price: 50, max_price: 95, fees: fees, finish_date: 5.days.from_now)
  end

  it "mostra a promoção atual, a melhor oferta e o ganho (empate: ajustar o preço da atual em vez de trocar)" do
    get "/api/promotions", params: { account_id: account.id }, headers: auth_headers(member)

    row = json["items"].find { |r| r["item_id"] == item.item_id }
    expect(row["current"]).to include("name" => "Campanha 20%", "price" => 80.0)
    expect(row["best"]).to include("name" => "Campanha 20%", "price" => 95.0, "action" => "editar_preco")
    expect(row["status"]["key"]).to eq("trocar")
    expect(row["gain"]).to be > 0
    expect(json["promotions"].first).to include("promotion_id" => "C-1", "active_items" => 1)
  end

  it "margem máxima por anúncio, aplicada aos outros anúncios do mesmo SKU (só administrador)" do
    patch "/api/promotions/items/#{item.item_id}/settings", params: { account_id: account.id, max_margin_pct: 15 }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    patch "/api/promotions/items/#{item.item_id}/settings",
      params: { account_id: account.id, min_margin_pct: 10, max_margin_pct: 15, apply_to_sku: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json["settings"]).to include("min_margin_pct" => 10.0, "max_margin_pct" => 15.0, "apply_to_sku" => true)
    expect(json["best"]["margin_pct"]).to be_within(0.01).of(15.0)
    expect(MlPromotionSetting.find_by(item_id: sibling.item_id)).to have_attributes(max_margin_pct: 15, apply_to_sku: true)
  end

  it "margem máxima menor que a mínima é recusada" do
    patch "/api/promotions/items/#{item.item_id}/settings", params: { account_id: account.id, min_margin_pct: 20, max_margin_pct: 10 }, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "exporta todas as ofertas em CSV" do
    get "/api/promotions/export", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response.media_type).to eq("text/csv")
    lines = response.body.lines
    expect(lines.size).to eq(3)
    expect(lines.last).to include("Evento")
  end

  it "aplicar e aplicar em lote são só para administrador; o lote vai para a fila" do
    post "/api/promotions/items/#{item.item_id}/apply", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    expect {
      post "/api/promotions/apply_best", params: { account_id: account.id, item_ids: [ item.item_id, "MLB-OUTRA-CONTA" ] }, headers: auth_headers(admin)
    }.to have_enqueued_job(Ml::PromotionsApplyJob).with(account.id, [ item.item_id ], admin.id)
    expect(json["queued"]).to eq(1)
  end

  it "margem máxima geral da empresa vale para anúncio sem margem própria" do
    company.update!(max_margin_pct: 15)

    get "/api/promotions", params: { account_id: account.id }, headers: auth_headers(member)

    row = json["items"].find { |r| r["item_id"] == item.item_id }
    expect(row["settings"]["effective_max_pct"]).to eq(15.0)
    expect(row["best"]["margin_pct"]).to be_within(0.01).of(15.0)
  end
end
