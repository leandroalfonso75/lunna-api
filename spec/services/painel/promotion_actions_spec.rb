require "rails_helper"

RSpec.describe Painel::PromotionActions do
  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 5, min_margin_pct: 9) }
  let(:account) { create(:ml_account, company: company, expires_at: 3.hours.from_now) }
  let(:user) { create(:user, :admin, company: company) }
  let!(:item) { create(:ml_item, ml_account: account, sku: "SKU-A", price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }
  let(:base) { "https://api.mercadolibre.com/seller-promotions/items/#{item.item_id}" }

  def offer(promotion_id, type, status:, max:, price: nil, meli: nil)
    MlPromotionOffer.create!(ml_account: account, item_id: item.item_id, promotion_id: promotion_id, promotion_type: type, name: promotion_id,
      status: status, price: price, original_price: 100, min_price: 50, max_price: max, meli_percentage: meli,
      fees: { "price" => max, "sale_fee" => max * 0.1, "percentage_fee" => 10, "fixed_fee" => 0 })
  end

  before do
    create(:olist_product, company: company, sku: "SKU-A", cost_price: 40, status: "A", kind: "S")
    allow(Ml::Sync::Promotions).to receive(:call) # as ofertas do teste já estão no banco
    offer("C-1", "SELLER_CAMPAIGN", status: "started", price: 80, max: 85)
    offer("P-2", "DEAL", status: "candidate", max: 95, meli: 2) # última promoção a 80: sobe no máximo 5%, até 84,00; o ML banca 2%
  end

  it "troca pela melhor oferta: sai da atual e entra na nova com o preço da regra, e registra" do
    leave = stub_request(:delete, base).with(query: { app_version: "v2", promotion_type: "SELLER_CAMPAIGN", promotion_id: "C-1" }).to_return(status: 200, body: "{}")
    join = stub_request(:post, base).with(query: { app_version: "v2" },
      body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 84.0 }.to_json).to_return(status: 201, body: "{}")

    result = described_class.apply(account, item.item_id, user: user)

    expect(result.ok).to be true
    expect(result.message).to include("trocou C-1 por P-2")
    expect(leave).to have_been_requested
    expect(join).to have_been_requested
    expect(MlPromotionAction.last).to have_attributes(kind: "trocar", ok: true, from_promotion_id: "C-1", to_promotion_id: "P-2", to_price: 84, user: user)
  end

  it "se o ML recusar a entrada, volta para a promoção anterior com o preço de antes" do
    stub_request(:delete, base).with(query: hash_including(promotion_id: "C-1")).to_return(status: 200, body: "{}")
    stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 84.0 }.to_json)
      .to_return(status: 400, body: { message: "item not eligible" }.to_json)
    back = stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN", deal_price: 80.0 }.to_json).to_return(status: 201, body: "{}")

    result = described_class.apply(account, item.item_id, user: user)

    expect(result.ok).to be false
    expect(result.message).to include("item not eligible", "voltou para C-1")
    expect(back).to have_been_requested
    expect(MlPromotionAction.last).to have_attributes(ok: false)
  end

  it "não aplica oferta abaixo da margem mínima" do
    company.update!(min_margin_pct: 40)

    result = described_class.apply(account, item.item_id, user: user)

    expect(result.ok).to be false
    expect(a_request(:any, /seller-promotions/)).not_to have_been_made
  end

  it "sai da promoção atual" do
    stub_request(:delete, base).with(query: hash_including(promotion_id: "C-1")).to_return(status: 200, body: "")

    result = described_class.leave(account, item.item_id, user: user)

    expect(result.ok).to be true
    expect(MlPromotionAction.last).to have_attributes(kind: "sair", ok: true)
  end

  it "403 do PolicyAgent vira aviso de falta de permissão de escrita no app, sem mexer no anúncio" do
    stub_request(:delete, base).with(query: hash_including(promotion_id: "C-1"))
      .to_return(status: 403, body: { status: 403, code: "PA_UNAUTHORIZED_RESULT_FROM_POLICIES" }.to_json)

    result = described_class.apply(account, item.item_id, user: user)

    expect(result.ok).to be false
    expect(result.message).to include("permissão de leitura de promoções")
    expect(a_request(:post, /seller-promotions/)).not_to have_been_made
  end
end
