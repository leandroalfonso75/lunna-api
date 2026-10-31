require "rails_helper"

RSpec.describe Painel::PromotionActions do
  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 5, min_margin_pct: 15) }
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
    offer("C-1", "SELLER_CAMPAIGN", status: "started", price: 80, max: 80) # faixa já no teto: não sobe para a mínima
    offer("P-2", "DEAL", status: "candidate", max: 95, meli: 2) # última promoção a 80: sobe no máximo 5%, até 84,00; o ML banca 2%
  end

  it "troca pela melhor oferta: sai da atual e entra na nova com o preço da regra, e registra" do
    leave = stub_request(:delete, base).with(query: { app_version: "v2", promotion_type: "SELLER_CAMPAIGN", promotion_id: "C-1" }).to_return(status: 200, body: "{}")
    join = stub_request(:post, base).with(query: { app_version: "v2" },
      body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 80.0 }.to_json).to_return(status: 201, body: "{}")

    result = described_class.apply(account, item.item_id, user: user)

    expect(result.ok).to be true
    expect(result.message).to include("trocou C-1 por P-2")
    expect(leave).to have_been_requested
    expect(join).to have_been_requested
    expect(MlPromotionAction.last).to have_attributes(kind: "trocar", ok: true, from_promotion_id: "C-1", to_promotion_id: "P-2", to_price: 80, user: user)
  end

  it "se o ML recusar a entrada, volta para a promoção anterior com o preço de antes" do
    stub_request(:delete, base).with(query: hash_including(promotion_id: "C-1")).to_return(status: 200, body: "{}")
    stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 80.0 }.to_json)
      .to_return(status: 400, body: { message: "item not eligible" }.to_json)
    back = stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN", deal_price: 80.0 }.to_json).to_return(status: 201, body: "{}")

    result = described_class.apply(account, item.item_id, user: user)

    expect(result.ok).to be false
    expect(result.message).to include("item not eligible", "voltou para C-1")
    expect(back).to have_been_requested
    expect(MlPromotionAction.last).to have_attributes(ok: false)
  end

  it "se o ML recusar a entrada e a volta, agenda nova tentativa em 1 hora" do
    stub_request(:delete, base).with(query: hash_including(promotion_id: "C-1")).to_return(status: 200, body: "{}")
    stub_request(:post, base).with(query: { app_version: "v2" }).to_return(status: 400, body: { message: "No candidates found for item" }.to_json)

    result = nil
    expect { result = described_class.apply(account, item.item_id, user: user) }.to have_enqueued_job(Ml::PromotionsApplyJob)
      .with(account.id, [ item.item_id ], user.id, { "promotion_id" => "P-2", "promotion_type" => "DEAL" })
    expect(result.ok).to be false
    expect(result.message).to include("ficou sem promoção", "Nova tentativa agendada")
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

  describe "aplicar mesmo assim e outro valor" do
    let(:p2) { { promotion_id: "P-2", promotion_type: "DEAL", action: "aderir" } }

    before { stub_request(:delete, base).with(query: hash_including(promotion_id: "C-1")).to_return(status: 200, body: "{}") }

    it "aplica a oferta barrada pela margem quando pedido, e guarda a regra ferida no Histórico" do
      company.update!(min_margin_pct: 40)
      join = stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 80.0 }.to_json)
        .to_return(status: 201, body: "{}")

      refused = described_class.apply(account, item.item_id, user: user, target: p2)
      expect(refused.ok).to be false
      expect(join).not_to have_been_requested

      result = described_class.apply(account, item.item_id, user: user, target: p2.merge(force: "true"))
      expect(result.ok).to be true
      expect(result.message).to include("Aplicado mesmo assim (abaixo da margem mínima)")
      expect(MlPromotionAction.last).to have_attributes(ok: true, to_promotion_id: "P-2", forced_reason: "abaixo da margem mínima")
    end

    it "mesmo assim sem preço: entra no preço que cabe nos limites, ferindo só a regra de aumento" do
      company.update!(min_margin_pct: 20) # hoje 80 (lucro 10, 12,5%); a mínima pede 87,28 no Evento (o ML banca 2%)
      join = stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 87.28 }.to_json)
        .to_return(status: 201, body: "{}")

      result = described_class.apply(account, item.item_id, user: user, target: p2.merge(force: true))

      expect(result.ok).to be true
      expect(join).to have_been_requested
      expect(MlPromotionAction.last).to have_attributes(to_price: 87.28, forced_reason: a_string_starting_with("aumentaria o preço de R$ 80,00 para R$ 87,28"))
    end

    it "aplica outro preço informado, mesmo passando do limite de aumento" do
      join = stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 90.0 }.to_json)
        .to_return(status: 201, body: "{}")

      expect(described_class.apply(account, item.item_id, user: user, target: p2.merge(price: "90")).ok).to be false

      result = described_class.apply(account, item.item_id, user: user, target: p2.merge(price: "90,00", force: true))
      expect(result.ok).to be true
      expect(join).to have_been_requested
      expect(MlPromotionAction.last).to have_attributes(to_price: 90, forced_reason: a_string_including("aumento"))
    end

    it "não passa da faixa de preço que o Mercado Livre aceita na oferta" do
      result = described_class.apply(account, item.item_id, user: user, target: p2.merge(price: "99", force: true))

      expect(result.ok).to be false
      expect(result.message).to include("só aceita até R$ 95,00")
      expect(a_request(:any, /seller-promotions/)).not_to have_been_made
    end
  end

  describe "oferta melhor que só começa depois" do
    before { MlPromotionOffer.find_by(promotion_id: "P-2").update!(start_date: 2.days.from_now) }

    it "não sai da atual: entra na nova e agenda a saída da atual para quando a nova começar" do
      join = stub_request(:post, base).with(query: { app_version: "v2" }, body: { promotion_id: "P-2", promotion_type: "DEAL", deal_price: 80.0 }.to_json)
        .to_return(status: 201, body: "{}")

      result = nil
      expect { result = described_class.apply(account, item.item_id, user: user) }.to have_enqueued_job(Ml::PromotionsHandoffJob)

      expect(result.ok).to be true
      expect(result.message).to include("até lá segue em C-1")
      expect(join).to have_been_requested
      expect(a_request(:delete, /seller-promotions/)).not_to have_been_made
      expect(MlPromotionAction.last).to have_attributes(kind: "agendar", ok: true)
    end

    it "quando a nova começa, sai da anterior" do
      MlPromotionOffer.find_by(promotion_id: "P-2").update!(status: "started", price: 80)
      leave = stub_request(:delete, base).with(query: hash_including(promotion_id: "C-1")).to_return(status: 200, body: "{}")

      result = described_class.new(account, nil, "rotina").handoff(item.item_id, { promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN" },
        { promotion_id: "P-2", promotion_type: "DEAL" })

      expect(result.ok).to be true
      expect(leave).to have_been_requested
      expect(MlPromotionAction.last).to have_attributes(kind: "sair", ok: true)
    end
  end

  it "com uma promoção programada (pending) e sem a atual, entra numa provisória e sai dela quando a programada começar" do
    MlPromotionOffer.find_by(promotion_id: "C-1").update!(status: "candidate", price: nil)
    MlPromotionOffer.find_by(promotion_id: "P-2").update!(status: "pending", price: 80, start_date: 10.days.from_now)
    offer("C-3", "PRICE_DISCOUNT", status: "candidate", max: 95)
    stub_request(:post, base).with(query: hash_including({})).to_return(status: 201, body: "{}")

    result = nil
    company.update!(max_margin_pct: 20) # preço cheio (25%) acima da máxima: precisa de promoção já
    result = nil
    expect { result = described_class.apply(account, item.item_id, user: user) }.to have_enqueued_job(Ml::PromotionsHandoffJob)
    expect(result.ok).to be true
    expect(MlPromotionAction.last).to have_attributes(kind: "aderir", to_type: "SELLER_CAMPAIGN").or have_attributes(kind: "aderir", to_type: "PRICE_DISCOUNT")
  end
end
