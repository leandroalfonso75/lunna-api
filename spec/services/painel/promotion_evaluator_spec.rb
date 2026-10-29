require "rails_helper"

RSpec.describe Painel::PromotionEvaluator do
  let(:account) { create(:ml_account) }
  let(:item) { build(:ml_item, ml_account: account, price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }

  def offer(type, status: "candidate", **attrs)
    MlPromotionOffer.new(ml_account: account, item_id: item.item_id, promotion_type: type, status: status, original_price: 100, **attrs)
  end

  def evaluator(min: nil, max: nil, min_price: nil, max_price: nil, ads: 0, cap: nil, current: nil)
    rules = described_class::Rules.new(min_pct: min, max_pct: max, min_price: min_price, max_price: max_price, tax_pct: 10, fixed_pct: 5, ads_unit: ads,
                                       price_cap: cap, current_price: current)
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

  it "a margem máxima é só uma barreira, e não vale para a oferta relâmpago" do
    e = evaluator(min: 15, max: 20)
    item.available_quantity = 10
    lightning = offer("LIGHTNING", min_price: 90, max_price: 95, payload: { "stock" => { "min" => 5 } },
      fees: { "price" => 95, "sale_fee" => 9.5, "percentage_fee" => 10, "fixed_fee" => 0 })

    expect(e.evaluate_offer(campaign)).to include(price: 83.34, valid: true)
    expect(e.evaluate_offer(smart)).to include(valid: false, reason: "acima da margem máxima")
    expect(evaluator(min: 10, max: 15).evaluate_offer(lightning)).to include(price: 90.0, valid: true)
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

  it "o aumento sobre a última promoção é limitado por faixa de preço" do
    expect(described_class.raise_pct_for(240)).to eq(2.0)
    expect(described_class.raise_pct_for(150)).to eq(3.0)
    expect(described_class.raise_pct_for(60)).to eq(5.0)
    expect(described_class.raise_pct_for(20)).to eq(7.0)

    # última promoção a 80 (faixa 50–99,99: até 5%, teto 84,00); a mínima de 20% pediria 90,91
    expect(evaluator(min: 15, current: 80).evaluate_offer(campaign)).to include(price: 83.34, valid: true)
    expect(evaluator(min: 20, current: 80).evaluate_offer(campaign)).to include(price: 84.0, valid: false)
    expect(evaluator(current: 80).evaluate_offer(smart)).to include(valid: false, reason: "aumento acima de 5% sobre a última promoção (R$ 80.00)")
  end

  it "mesmo dentro do limite, o aumento não passa para a casa de cem seguinte" do
    # última promoção a 198 (3% = 203,94), a mínima de 50% pediria 200: fica em 199,99
    wide = offer("SELLER_CAMPAIGN", min_price: 100, max_price: 220, fees: { "price" => 220, "sale_fee" => 22, "percentage_fee" => 10, "fixed_fee" => 0 })
    fixed = offer("SMART", price: 201, meli_percentage: 1, fees: { "price" => 201, "sale_fee" => 20.1, "percentage_fee" => 10, "fixed_fee" => 0 })
    e = evaluator(min: 50, current: 198)

    expect(e.evaluate_offer(wide)[:price]).to eq(199.99)
    expect(e.evaluate_offer(fixed)).to include(valid: false, reason: "passaria da casa dos R$ 200")
  end

  describe "trava de lucro" do
    # hoje: campanha a 90 (lucro 17,50, margem 19,44%), dentro dos limites
    let(:current) { offer("SELLER_CAMPAIGN", status: "started", price: 90, min_price: 50, max_price: 95, fees: campaign.fees) }
    let(:cheaper) { offer("SMART", price: 85, meli_percentage: 2, fees: { "price" => 85, "sale_fee" => 8.5, "percentage_fee" => 10, "fixed_fee" => 0 }) }

    def guarded(**opts)
      rules = described_class::Rules.new(min_pct: 10, max_pct: nil, tax_pct: 10, fixed_pct: 5, ads_unit: 0, current_price: 90, **opts)
      described_class.new(item: item, cost: 40, rules: rules)
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
      rules = described_class::Rules.new(min_pct: 10, max_pct: 15, tax_pct: 10, fixed_pct: 5, ads_unit: 0, current_price: 90)
      e = described_class.new(item: item, cost: 40, rules: rules)
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
