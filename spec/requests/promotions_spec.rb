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
      name: "Campanha 20%", status: "started", price: 90, original_price: 100, min_price: 50, max_price: 95, fees: fees)
    MlPromotionOffer.create!(ml_account: account, item_id: item.item_id, promotion_id: "P-2", promotion_type: "DEAL",
      name: "Evento", status: "candidate", original_price: 100, min_price: 50, max_price: 90, meli_percentage: 2, fees: fees,
      finish_date: 5.days.from_now) # o ML banca 2% do preço original: no mesmo preço, rende mais
  end

  it "mostra a promoção atual e a melhor oferta; dentro dos limites, não troca por oferta que reduz o lucro" do
    get "/api/promotions", params: { account_id: account.id }, headers: auth_headers(member)

    row = json["items"].find { |r| r["item_id"] == item.item_id }
    # hoje: 90 (lucro 17,50, margem 19,44%), dentro da mínima de 9%: buscar a mínima reduziria o lucro
    expect(row["current"]).to include("name" => "Campanha 20%", "price" => 90.0)
    expect(row["best"]).to include("name" => "Campanha 20%", "price" => 90.0, "action" => "manter")
    expect(row["status"]["key"]).to eq("ok")
    expect(json["promotions"].first).to include("promotion_id" => "C-1", "active_items" => 1)
  end

  it "com permissão para reduzir a margem, desce o preço até a tolerância" do
    company.update!(promo_allow_margin_drop: true, promo_margin_drop_tolerance: 5)

    get "/api/promotions", params: { account_id: account.id }, headers: auth_headers(member)

    row = json["items"].find { |r| r["item_id"] == item.item_id }
    expect(row["best"]).to include("name" => "Campanha 20%", "action" => "editar_preco")
    expect(row["best"]["margin_pct"]).to be_within(0.02).of(14.44)
    expect(row["status"]["key"]).to eq("trocar")
    expect(row["gain"]).to be < 0
  end

  it "margem máxima por anúncio, aplicada aos outros anúncios do mesmo SKU (só administrador)" do
    patch "/api/promotions/items/#{item.item_id}/settings", params: { account_id: account.id, max_margin_pct: 15 }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    patch "/api/promotions/items/#{item.item_id}/settings",
      params: { account_id: account.id, min_margin_pct: 10, max_margin_pct: 15, apply_to_sku: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json["settings"]).to include("min_margin_pct" => 10.0, "max_margin_pct" => 15.0, "apply_to_sku" => true)
    expect(json["best"]["margin_pct"]).to be_within(0.01).of(10.0) # acima da máxima: vai para perto da mínima
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
    expect(row["status"]["key"]).to eq("acima_maxima")
    expect(row["best"]["margin_pct"]).to be_within(0.01).of(9.0)
  end

  it "limites por valor apagam a margem do anúncio, e valem também para as outras variações do produto" do
    parent = create(:olist_product, company: company, sku: "PAI", status: "A", kind: "V", variation_kind: "P")
    OlistProduct.where(company_id: company.id, sku: "SKU-A").update_all(parent_olist_id: parent.olist_id, variation_kind: "V")
    create(:olist_product, company: company, sku: "SKU-B", status: "A", kind: "S", variation_kind: "V", parent_olist_id: parent.olist_id)
    other_variation = create(:ml_item, ml_account: account, sku: "SKU-B")

    patch "/api/promotions/items/#{item.item_id}/settings",
      params: { account_id: account.id, limit_mode: "price", min_price: 60, max_price: 90, min_margin_pct: 30, apply_to_variations: true },
      headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json["settings"]).to include("limit_mode" => "price", "min_price" => 60.0, "max_price" => 90.0, "min_margin_pct" => nil)
    expect(json["best"]["price"]).to eq(90.0)
    expect(json["variation_items"].map { |v| v["item_id"] }).to eq([ other_variation.item_id ])
    expect(MlPromotionSetting.find_by(item_id: other_variation.item_id)).to have_attributes(limit_mode: "price", max_price: 90)
  end

  it "margem pós Ads: custo de Ads por unidade dos últimos 15 dias" do
    MlAdItemDaily.create!(ml_account: account, item_id: item.item_id, date: 3.days.ago.to_date, cost: 30)
    order = MlOrder.create!(order_id: 77, ml_account: account, status: "paid", date_created: 3.days.ago, total_amount: 100)
    MlOrderItem.create!(order_id: order.order_id, item_id: item.item_id, quantity: 3, unit_price: 100, sale_fee: 10)

    get "/api/promotions/items/#{item.item_id}", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["ads"]).to include("spend" => 30.0, "units" => 3, "unit" => 10.0, "days" => 15)
    expect(json["current"]["costs"]["ads"]).to eq(10.0)
  end

  it "aplicar pode levar a mesma promoção aos outros anúncios do SKU, em fila" do
    allow(Painel::PromotionActions).to receive(:apply).and_return(Painel::PromotionActions::Result.new(ok: true, message: "Anúncio entrou em P-2."))

    expect {
      post "/api/promotions/items/#{item.item_id}/apply",
        params: { account_id: account.id, promotion_id: "P-2", promotion_type: "DEAL", also_sku: true }, headers: auth_headers(admin)
    }.to have_enqueued_job(Ml::PromotionsApplyJob).with(account.id, [ sibling.item_id ], admin.id, { "promotion_id" => "P-2", "promotion_type" => "DEAL" })
    expect(json).to include("queued" => 1)
    expect(json["message"]).to include("mais 1 anúncios")
  end

  it "a melhor oferta nunca fica acima do preço cheio do anúncio" do
    get "/api/promotions/items/#{item.item_id}", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["best"]["price"]).to be <= 100.0
  end

  it "anúncio em que nenhuma oferta cabe nas regras vai para revisar, com a regra que barrou" do
    company.update!(min_margin_pct: 40)

    get "/api/promotions", params: { account_id: account.id, status: "para_revisar" }, headers: auth_headers(member)

    row = json["items"].find { |r| r["item_id"] == item.item_id }
    expect(row["status"]["key"]).to eq("para_revisar")
    expect(row["review"]["label"]).to eq("abaixo da margem mínima")
    expect(row["review"]["blocked_best"]).to include("name" => "Evento", "reason" => "abaixo da margem mínima")
    expect(row["review"]["blocked_best"]["shortfall"]).to include("mínima 40.0%")
    expect(row["review"]["suggested"]).to include("field" => "min_margin_pct")
    expect(json["counts"]["para_revisar"]).to be >= 1
  end

  it "variações do mesmo produto ficam agrupadas numa linha, e a nota de regras do anúncio é guardada" do
    parent = create(:olist_product, company: company, sku: "PAI", description: "Produto Pai", status: "A", kind: "V", variation_kind: "P")
    OlistProduct.where(company_id: company.id, sku: "SKU-A").update_all(parent_olist_id: parent.olist_id, variation_kind: "V")
    create(:olist_product, company: company, sku: "SKU-B", status: "A", kind: "S", variation_kind: "V", parent_olist_id: parent.olist_id)
    create(:ml_item, ml_account: account, sku: "SKU-B")

    patch "/api/promotions/items/#{item.item_id}/settings",
      params: { account_id: account.id, limit_mode: "margin", rules_note: "  Nunca entrar em relâmpago  ", apply_to_variations: true }, headers: auth_headers(admin)
    expect(json["settings"]["rules_note"]).to eq("Nunca entrar em relâmpago")

    get "/api/promotions", params: { account_id: account.id }, headers: auth_headers(member)

    group = json["items"].find { |r| r["group"] }
    expect(group).to include("title" => "Produto Pai", "sku" => "PAI", "count" => 3, "variations" => 2)
    expect(group["children"].map { |c| c["sku"] }.uniq).to contain_exactly("SKU-A", "SKU-B")
    expect(group["children"].find { |c| c["sku"] == "SKU-B" }["notes"]).to eq("Nunca entrar em relâmpago")
  end

  it "simular agora vai para a fila (só administrador) e o relatório mostra antes e depois" do
    post "/api/promotions/runs", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    expect {
      post "/api/promotions/runs", params: { account_id: account.id }, headers: auth_headers(admin)
    }.to have_enqueued_job(Ml::PromotionsRoutineJob).with(account.id, admin.id)

    allow(Ml::Sync::Promotions).to receive(:call)
    company.update!(promo_allow_margin_drop: true, promo_margin_drop_tolerance: 5)
    run = Painel::PromotionRoutine.call(account, mode: "simulation", trigger: "manual")
    get "/api/promotions/runs/#{run.id}", params: { account_id: account.id }, headers: auth_headers(member)

    # a melhor seria ajustar o preço da campanha atual: a rotina não faz isso (só sem promoção ou campanha do ML melhor)
    row = json["rows"].find { |r| r["item_id"] == item.item_id }
    expect(row).to include("changes" => false, "ok" => true)
    expect(row["reason"]).to include("não ajusta o preço")
    expect(row["before"]["price"]).to eq(90.0)
    get "/api/promotions/runs", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["routine"]).to eq("enabled" => false, "mode" => "simulation")
    expect(json["runs"].first["mode_label"]).to eq("Simulação")
  end

  it "não automatizar: marca o anúncio e o SKU, mostra na aba própria e tira do lote, sem apagar os limites" do
    MlPromotionSetting.create!(ml_account: account, item_id: item.item_id, min_margin_pct: 12)

    patch "/api/promotions/items/#{item.item_id}/automation",
      params: { account_id: account.id, enabled: false, apply_to_sku: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json["updated"]).to eq(2)
    expect(MlPromotionSetting.find_by(item_id: item.item_id)).to have_attributes(automation_enabled: false, min_margin_pct: 12)
    expect(MlPromotionSetting.find_by(item_id: sibling.item_id).automation_enabled).to be false

    get "/api/promotions", params: { account_id: account.id, status: "nao_automatizados" }, headers: auth_headers(member)
    expect(json["counts"]["nao_automatizados"]).to eq(2)
    expect(json["items"].map { |r| r["item_id"] }).to contain_exactly(item.item_id, sibling.item_id)
    expect(json["items"].find { |r| r["item_id"] == item.item_id }["best"]).to be_present # a melhor oferta segue sugerida

    post "/api/promotions/apply_best", params: { account_id: account.id, item_ids: [ item.item_id ] }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "filtro Catálogo: ganhando ou perdendo, o preço para ganhar e a oferta que chega nele" do
    item.update!(catalog_listing: true, catalog_status: "competing", catalog_price_to_win: 85, catalog_winner_price: 86)

    get "/api/promotions", params: { account_id: account.id, status: "catalogo" }, headers: auth_headers(member)

    expect(json["counts"]).to include("catalogo" => 1, "catalogo_perdendo" => 1)
    expect(json["items"].map { |r| r["item_id"] }).to eq([ item.item_id ])
    info = json["items"].first["catalog_info"]
    expect(info).to include("state" => "perdendo", "price_to_win" => 85.0, "price_today" => 90.0)
    expect(info["suggestion"]).to include("price" => 85.0)
  end
end
