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
  let(:campaign) { offer("SELLER_CAMPAIGN", min_price: 50, max_price: 95, fees: { "price" => 95, "sale_fee" => 9.5, "percentage_fee" => 10, "fixed_fee" => 0 }) }

  it "soma a parte do ML e usa o maior preço permitido nas campanhas de faixa" do
    e = evaluator
    smart_eval = e.evaluate_offer(smart)
    campaign_eval = e.evaluate_offer(campaign)

    expect(smart_eval).to include(price: 90.0, meli_amount: 2.0, profit: 19.5, valid: true)
    expect(campaign_eval).to include(price: 95.0, profit: 21.25, margin_pct: 22.37)
    expect(e.best([ smart_eval, campaign_eval ])[:offer]).to eq(campaign)
  end

  it "com margem máxima, desce o preço da faixa até ela" do
    result = evaluator(max: 15).evaluate_offer(campaign)

    expect(result[:price]).to eq(83.33)
    expect(result[:margin_pct]).to be_within(0.01).of(15.0)
  end

  it "oferta abaixo da margem mínima não serve, e cupom não entra na escolha" do
    e = evaluator(min: 25)

    expect(e.evaluate_offer(campaign)).to include(valid: false, reason: "abaixo da margem mínima")
    expect(e.evaluate_offer(offer("SELLER_COUPON_CAMPAIGN", fixed_amount: 4))).to include(valid: false)
  end

  it "empate de margem fica com a promoção atual" do
    current = offer("SELLER_CAMPAIGN", status: "started", min_price: 50, max_price: 95, fees: campaign.fees, finish_date: 1.day.from_now)
    other = offer("SELLER_CAMPAIGN", min_price: 50, max_price: 95, fees: campaign.fees, finish_date: 10.days.from_now)
    e = evaluator

    expect(e.best(e.evaluate([ other, current ]))[:offer]).to eq(current)
  end

  it "desconta o custo de Ads por unidade (margem pós Ads) e devolve os custos linha a linha" do
    result = evaluator(ads: 5).evaluate_offer(campaign)

    expect(result).to include(price: 95.0, profit: 16.25)
    expect(result[:costs]).to eq(cost: 40.0, fee: 9.5, shipping: 10.0, tax: 9.5, fixed_expenses: 4.75, ads: 5.0, meli_amount: 0.0)
  end

  it "com margem máxima, conta o Ads ao descer o preço" do
    result = evaluator(max: 15, ads: 6).evaluate_offer(campaign)

    expect(result[:price]).to eq(93.33)
    expect(result[:margin_pct]).to be_within(0.01).of(15.0)
  end

  it "por valor: o preço da faixa fica até o valor máximo e oferta abaixo do valor mínimo não serve" do
    expect(evaluator(max_price: 88).evaluate_offer(campaign)).to include(price: 88.0, valid: true)
    expect(evaluator(min_price: 92).evaluate_offer(smart)).to include(valid: false, reason: "abaixo do valor mínimo")
  end

  it "o preço cheio do anúncio é o teto: a faixa fica até ele e oferta fixa acima dele não serve" do
    expect(evaluator(cap: 85).evaluate_offer(campaign)).to include(price: 85.0, valid: true)
    expect(evaluator(cap: 85).evaluate_offer(smart)).to include(valid: false, reason: "acima do preço cheio do anúncio")
  end

  it "o aumento sobre a última promoção é limitado por faixa de preço" do
    expect(described_class.raise_pct_for(240)).to eq(2.0)
    expect(described_class.raise_pct_for(150)).to eq(3.0)
    expect(described_class.raise_pct_for(60)).to eq(5.0)
    expect(described_class.raise_pct_for(20)).to eq(7.0)

    # última promoção a 80 (faixa 50–99,99: até 5%): a faixa da campanha fica em 84,00 e a SMART a 90 não serve
    expect(evaluator(current: 80).evaluate_offer(campaign)).to include(price: 84.0, valid: true)
    expect(evaluator(current: 80).evaluate_offer(smart)).to include(valid: false, reason: "aumento acima de 5% sobre a última promoção (R$ 80.00)")
  end

  it "mesmo dentro do limite, o aumento não passa para a casa de cem seguinte" do
    # última promoção a 198 (3% = 203,94), faixa até 220: fica em 199,99
    wide = offer("SELLER_CAMPAIGN", min_price: 100, max_price: 220, fees: { "price" => 220, "sale_fee" => 22, "percentage_fee" => 10, "fixed_fee" => 0 })
    fixed = offer("SMART", price: 201, meli_percentage: 1, fees: { "price" => 201, "sale_fee" => 20.1, "percentage_fee" => 10, "fixed_fee" => 0 })
    e = evaluator(current: 198)

    expect(e.evaluate_offer(wide)[:price]).to eq(199.99)
    expect(e.evaluate_offer(fixed)).to include(valid: false, reason: "passaria da casa dos R$ 200")
  end
end
