require "rails_helper"

RSpec.describe Painel::PromotionEvaluator do
  let(:account) { create(:ml_account) }
  let(:item) { build(:ml_item, ml_account: account, price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }

  def offer(type, status: "candidate", **attrs)
    MlPromotionOffer.new(ml_account: account, item_id: item.item_id, promotion_type: type, status: status, original_price: 100, **attrs)
  end

  def evaluator(min: nil, max: nil, min_price: nil, max_price: nil, ads: 0, cap: nil, current: nil, **opts)
    rules = described_class::Rules.new(min_pct: min, max_pct: max, min_price: min_price, max_price: max_price, tax_pct: 10, fixed_pct: 5, ads_unit: ads,
                                       price_cap: cap, current_price: current, basis: "after_ads", target: "min", allow_increase: true,
                                       allow_lightning: true, **opts)
    described_class.new(item: item, cost: 40, rules: rules)
  end

  let(:smart) { offer("SMART", price: 90, meli_percentage: 2, fees: { "price" => 90, "sale_fee" => 9, "percentage_fee" => 10, "fixed_fee" => 0 }) }
  let(:campaign) { offer("DEAL", min_price: 50, max_price: 95, fees: { "price" => 95, "sale_fee" => 9.5, "percentage_fee" => 10, "fixed_fee" => 0 }) }

  # Faixa da campanha: lucro = 0,75 × preço − 50 − Ads (tarifa 10%, imposto 10%, despesas 5%, custo 40, frete 10).
  it "mira a margem mínima: nas de faixa, o menor preço que ainda dá a mínima; a melhor é a de menor margem" do
    e = evaluator(min: 15)
    smart_eval = e.evaluate_offer(smart)
    campaign_eval = e.evaluate_offer(campaign)

    expect(smart_eval).to include(price: 90.0, meli_amount: 2.0, profit: 19.5, valid: true)
    expect(campaign_eval).to include(price: 83.34, valid: true)
    expect(campaign_eval[:margin_pct]).to be_within(0.01).of(15.0)
    expect(e.best([ smart_eval, campaign_eval ])[:offer]).to eq(campaign)
  end

  it "a margem máxima é só uma barreira com alvo na mínima; com alvo na máxima, o preço vai para ela" do
    e = evaluator(min: 15, max: 20)

    expect(e.evaluate_offer(campaign)).to include(price: 83.34, valid: true)
    expect(e.evaluate_offer(smart)).to include(valid: false, reason: "acima da margem máxima")

    top = evaluator(min: 15, max: 20, target: "max")
    expect(top.evaluate_offer(campaign)).to include(price: 90.9, valid: true)
    expect(top.evaluate_offer(campaign)[:margin_pct]).to be_within(0.05).of(20.0)
    expect(top.best([ top.evaluate_offer(campaign), top.evaluate_offer(offer("DEAL", price: 86, fees: { "price" => 86, "sale_fee" => 8.6, "percentage_fee" => 10, "fixed_fee" => 0 })) ])[:price]).to eq(90.9)
  end

  it "oferta relâmpago só entra com autorização, e dentro dos limites" do
    item.available_quantity = 10
    lightning = offer("LIGHTNING", min_price: 50, max_price: 95, payload: { "stock" => { "min" => 5 }, "price" => 95 },
      fees: { "price" => 95, "sale_fee" => 9.5, "percentage_fee" => 10, "fixed_fee" => 0 })

    expect(evaluator(min: 10, allow_lightning: false).evaluate_offer(lightning)).to include(valid: false, reason: described_class::LIGHTNING_REASON)
    expect(evaluator(min: 10, allow_lightning: true).evaluate_offer(lightning)).to include(valid: true)
    expect(evaluator(min: 30, allow_lightning: true).evaluate_offer(lightning)).to include(valid: false, reason: "abaixo da margem mínima")
  end

  it "margem antes do Ads: os limites ignoram o Ads, mas o lucro pós Ads segue na conta" do
    before = evaluator(min: 15, ads: 6, basis: "before_ads").evaluate_offer(campaign)
    after = evaluator(min: 15, ads: 6, basis: "after_ads").evaluate_offer(campaign)

    expect(before).to include(price: 83.34, valid: true)
    expect(before[:margin_before_ads_pct]).to be_within(0.01).of(15.0)
    expect(before[:profit]).to eq(before[:profit_before_ads] - 6)
    expect(after).to include(price: 93.34, valid: true)
  end

  it "prefere as campanhas do ML; desconto próprio só se nenhuma couber; campanha do vendedor não é escolhida" do
    seller = offer("SELLER_CAMPAIGN", min_price: 50, max_price: 95, fees: campaign.fees)
    own = offer("PRICE_DISCOUNT", min_price: 50, max_price: 95, fees: campaign.fees)
    e = evaluator(min: 15)

    expect(e.best(e.evaluate([ seller, own, smart ]))[:offer]).to eq(smart) # 21,7% numa do ML vence 15% no desconto próprio
    expect(e.best(e.evaluate([ seller, own ]))[:offer]).to eq(own)
    expect(e.best(e.evaluate([ seller ]))).to be_nil
  end

  it "oferta abaixo da margem mínima não serve, e cupom não entra na escolha" do
    e = evaluator(min: 25)

    expect(e.evaluate_offer(campaign)).to include(valid: false, reason: "abaixo da margem mínima")
    expect(e.evaluate_offer(offer("SELLER_COUPON_CAMPAIGN", fixed_amount: 4))).to include(valid: false)
  end

  it "empate de margem fica com a promoção atual" do
    current = offer("DEAL", status: "started", min_price: 50, max_price: 95, fees: campaign.fees, finish_date: 1.day.from_now)
    other = offer("DEAL", min_price: 50, max_price: 95, fees: campaign.fees, finish_date: 10.days.from_now)
    e = evaluator(min: 10)

    expect(e.best(e.evaluate([ other, current ]))[:offer]).to eq(current)
  end

  it "desconta o custo de Ads por unidade (margem pós Ads) e devolve os custos linha a linha" do
    result = evaluator(ads: 5).evaluate_offer(smart)

    expect(result).to include(price: 90.0, profit: 14.5)
    expect(result[:costs]).to eq(cost: 40.0, fee: 9.0, shipping: 10.0, tax: 9.0, fixed_expenses: 4.5, ads: 5.0, meli_amount: 2.0)
  end

  it "conta o Ads ao buscar o preço da margem mínima" do
    result = evaluator(min: 15, ads: 6).evaluate_offer(campaign)

    expect(result[:price]).to eq(93.34)
    expect(result[:margin_pct]).to be_within(0.01).of(15.0)
  end

  it "por valor: o preço da faixa fica no valor mínimo e oferta fora dos valores não serve" do
    expect(evaluator(min_price: 88).evaluate_offer(campaign)).to include(price: 88.0, valid: true)
    expect(evaluator(min_price: 92).evaluate_offer(smart)).to include(valid: false, reason: "abaixo do valor mínimo")
    expect(evaluator(max_price: 88).evaluate_offer(smart)).to include(valid: false, reason: "acima do valor máximo")
  end

  it "o preço cheio do anúncio é o teto: se a mínima pede mais que ele, a oferta não serve" do
    expect(evaluator(min: 15, cap: 85).evaluate_offer(campaign)).to include(price: 83.34, valid: true)
    expect(evaluator(min: 20, cap: 85).evaluate_offer(campaign)).to include(price: 85.0, valid: false, reason: "abaixo da margem mínima")
    expect(evaluator(cap: 85).evaluate_offer(smart)).to include(valid: false, reason: "acima do preço cheio do anúncio")
  end

  it "sem permissão de aumento, o preço final não sobe enquanto a promoção atual vale" do
    # hoje: campanha a 80 (acima da mínima de 5%); a mínima de 20% pediria 90,91 e a SMART fica a 90
    current = offer("SELLER_CAMPAIGN", status: "started", price: 80, min_price: 50, max_price: 95, fees: campaign.fees)
    e = evaluator(min: 5, max: 40, allow_increase: false)
    evaluated = e.evaluate([ current, smart, campaign ])

    expect(evaluated.find { |x| x[:offer] == smart }).to include(valid: false, reason: a_string_starting_with("aumentaria o preço de R$ 80,00 para R$ 90,00"))
    expect(evaluated.find { |x| x[:offer] == campaign }[:price]).to be <= 80.0

    allowed = evaluator(min: 5, max: 40, allow_increase: true)
    expect(allowed.evaluate([ current, smart ]).find { |x| x[:offer] == smart }).to include(valid: true)
  end

  describe "trava de lucro" do
    # hoje: campanha a 90 (lucro 17,50, margem 19,44%), dentro dos limites
    let(:current) { offer("SELLER_CAMPAIGN", status: "started", price: 90, min_price: 50, max_price: 95, fees: campaign.fees) }
    let(:cheaper) { offer("SMART", price: 85, meli_percentage: 2, fees: { "price" => 85, "sale_fee" => 8.5, "percentage_fee" => 10, "fixed_fee" => 0 }) }

    def guarded(**opts)
      evaluator(min: 10, current: 90, **opts)
    end

    it "sem permissão, não troca por oferta que reduz o lucro" do
      e = guarded
      evaluated = e.evaluate([ current, cheaper ])

      expect(evaluated.find { |x| x[:offer] == cheaper }).to include(valid: false, reason: "reduziria o lucro de R$ 17,50 para R$ 15,75 por unidade")
      expect(e.best(evaluated)).to include(as_is: true)
    end

    it "com permissão, desce até a tolerância de margem" do
      e = guarded(allow_margin_drop: true, margin_drop_tol: 3)
      best = e.best(e.evaluate([ current, cheaper ]))

      expect(best).to include(as_is: false, valid: true)
      expect(best[:offer]).to eq(current)
      expect(best[:margin_pct]).to be_within(0.02).of(16.44)
    end

    it "fora dos limites (acima da máxima), não há trava: vai para a margem mais perto da mínima" do
      e = evaluator(min: 10, max: 15, current: 90)
      best = e.best(e.evaluate([ current, cheaper ]))

      expect(best[:price]).to eq(76.93)
      expect(best[:margin_pct]).to be_within(0.01).of(10.0)
    end
  end

  it "relâmpago entra reservando o estoque sugerido pelo ML, se o anúncio tiver estoque" do
    item.available_quantity = 10
    lightning = offer("LIGHTNING", min_price: 50, max_price: 95, payload: { "stock" => { "min" => 5, "max" => 12 } },
      fees: { "price" => 95, "sale_fee" => 9.5, "percentage_fee" => 10, "fixed_fee" => 0 })
    expect(lightning.stock_reserved).to eq(5)
    expect(evaluator.evaluate_offer(lightning)).to include(valid: true)

    item.available_quantity = 3
    expect(evaluator.evaluate_offer(lightning)).to include(valid: false, reason: "estoque insuficiente para reservar (pede 5, tem 3)")
  end
end
