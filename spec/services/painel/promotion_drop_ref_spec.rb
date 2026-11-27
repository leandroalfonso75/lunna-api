require "rails_helper"

# Referência fixa da redução de margem em Promoções ("travar a escada", 27/11/2026).
RSpec.describe Painel::PromotionDropRef do
  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 5, min_margin_pct: 9, promo_allow_margin_drop: true, promo_margin_drop_tolerance: 5) }
  let(:account) { create(:ml_account, company: company, expires_at: 3.hours.from_now) }
  let(:user) { create(:user, :admin, company: company) }
  let!(:item) { create(:ml_item, ml_account: account, sku: "SKU-A", price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }
  let(:fees) { { "price" => 95, "sale_fee" => 9.5, "percentage_fee" => 10, "fixed_fee" => 0 } }
  let(:base) { "https://api.mercadolibre.com/seller-promotions/items/#{item.item_id}" }

  before do
    create(:olist_product, company: company, sku: "SKU-A", cost_price: 40, status: "A", kind: "S")
    allow(Ml::Sync::Promotions).to receive(:call)
    MlPromotion.create!(ml_account: account, promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN", name: "Campanha", status: "started")
    MlPromotionOffer.create!(ml_account: account, item_id: item.item_id, promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN",
      name: "Campanha", status: "started", price: 90, original_price: 100, min_price: 50, max_price: 95, fees: fees)
  end

  def row = Painel::PromotionsQuery.call(account, {})[:items].find { |r| r[:item_id] == item.item_id }
  def key = described_class.key_for(company, nil, 40.0)

  def stub_ml
    stub_request(:delete, base).with(query: hash_including({})).to_return(status: 200, body: "{}")
    stub_request(:post, base).with(query: hash_including({})).to_return(status: 201, body: "{}")
  end

  # o ML aceitou: a campanha passa a valer no preço aplicado (o que a próxima leitura da Central traria)
  def ml_now_at(price) = MlPromotionOffer.find_by(item_id: item.item_id, promotion_id: "C-1").update!(price: price)

  it "a 1ª redução da automação grava a margem de antes; nos dias seguintes a escada fica travada" do
    expect(row[:status][:key]).to eq("baixar_alvo")
    stub_ml

    result = Painel::PromotionActions.apply(account, item.item_id, source: "rotina")
    expect(result.ok).to be true
    ref = account.ml_promotion_drop_refs.find_by(item_id: item.item_id)
    expect(ref).to have_attributes(source: "automacao")
    expect(ref.margin_pct.to_f).to be_within(0.02).of(19.44)
    expect(ref.log.last["note"]).to include("antes de baixar")

    ml_now_at(MlPromotionAction.last.to_price)
    3.times do
      r = row
      expect(r[:status][:key]).to eq("ok") # já usou os 5 p.p. abaixo da referência: não desce mais
      expect(r[:drop_ref]).to include(source: "automacao", tolerance_pp: 5.0)
      expect(r[:drop_ref][:used_pp]).to be_within(0.03).of(5.0)
    end

    # sem a referência (como era antes), desceria de novo
    account.ml_promotion_drop_refs.delete_all
    expect(row[:status][:key]).to eq("baixar_alvo")
  end

  it "decisão manual pela tela grava a margem nova como referência" do
    stub_ml
    described_class.record!(account, item.item_id, 22, source: "automacao", key: key) # pode descer até 17%

    result = Painel::PromotionActions.apply(account, item.item_id, user: user, source: "tela")

    expect(result.ok).to be true
    ref = account.ml_promotion_drop_refs.find_by(item_id: item.item_id)
    expect(ref).to have_attributes(source: "manual", user: user)
    expect(ref.margin_pct.to_f).to be_within(0.05).of(MlPromotionAction.last.to_margin_pct.to_f)
    expect(ref.log.size).to eq(2)
  end

  it "ciente e mudança de tolerância renovam a referência (vale a margem de hoje), sem apagar o histórico" do
    described_class.record!(account, item.item_id, 25, source: "automacao", key: key)
    expect(row[:drop_ref]).to include(ref_pct: 25.0, source: "automacao")

    company.update!(promo_margin_drop_tolerance: 3)
    expect(row[:drop_ref]).to include(source: nil, renewed: true, tolerance_pp: 3.0)
    expect(row[:drop_ref][:ref_pct]).to be_within(0.02).of(19.44)

    company.update!(promo_margin_drop_tolerance: 5)
    expect(row[:drop_ref]).to include(ref_pct: 25.0)
    Painel::PromotionSettings.set_review_dismissed(account, item.item_id, true, user)
    expect(row[:drop_ref]).to include(source: nil, renewed: true)
    expect(account.ml_promotion_drop_refs.find_by(item_id: item.item_id).log.last).to include("note" => "ciente, nada a ser feito", "user" => user.name)
  end

  it "implantação: grava a margem de hoje como referência inicial, uma vez só" do
    expect(described_class.initialize_all!(account)).to eq(1)
    expect(account.ml_promotion_drop_refs.find_by(item_id: item.item_id)).to have_attributes(source: "inicial")
    expect(described_class.initialize_all!(account)).to eq(0)
    expect(row[:status][:key]).to eq("baixar_alvo") # partindo de hoje, ainda há 5 p.p. de tolerância
  end

  it "no Histórico, troca ou ajuste que reduziu o lucro aparece como \"Baixou o preço até o alvo\"" do
    expect(Painel::PromotionsQuery.kind_label("ajustar_preco", -0.32)).to eq("Baixou o preço até o alvo")
    expect(Painel::PromotionsQuery.kind_label("trocar", 1.5)).to eq("Trocou")
    expect(Painel::PromotionsQuery.kind_label("sair", -3)).to eq("Saiu")
  end
end
