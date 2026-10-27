require "rails_helper"

RSpec.describe Painel::PromotionEvaluator do
  let(:account) { create(:ml_account) }
  let(:item) { build(:ml_item, ml_account: account, price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }

  def offer(type, status: "candidate", **attrs)
    MlPromotionOffer.new(ml_account: account, item_id: item.item_id, promotion_type: type, status: status, original_price: 100, **attrs)
  end

  def evaluator(min: nil, max: nil, min_price: nil, max_price: nil, ads: 0)
    rules = described_class::Rules.new(min_pct: min, max_pct: max, min_price: min_price, max_price: max_price, tax_pct: 10, fixed_pct: 5, ads_unit: ads)
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
end
