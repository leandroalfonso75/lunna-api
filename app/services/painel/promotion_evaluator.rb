# Margem de cada oferta de promoção de um anúncio e a melhor delas (seção Promoções).
#
#   lucro (pós Ads) = preço + parte do ML − custo − tarifa − frete − imposto − despesas fixas − Ads
#   margem = lucro ÷ preço
#
# - Ads: custo de Ads por unidade do anúncio nos últimos 15 dias (gasto ÷ unidades vendidas); sem histórico, zero.
# - Limites: por margem (mínima/máxima, %) ou por valor (preço mínimo/máximo, R$), um ou outro.
# - Preço nunca sobe: a oferta parte do preço do anúncio e não pode ficar acima do preço de venda de hoje (price_cap:
#   o da promoção atual ou, sem promoção, o do anúncio). Subir o preço acima de R$ 79 obriga o frete grátis, pago pelo
#   vendedor.
# - Parte do ML: nas ofertas com desconto dividido (meli_percentage), o ML banca esse % do preço original.
# - Tarifa: a do ML no preço da oferta (Ml::Sync::Promotions guarda em `fees`); fora desse preço,
#   % da tarifa × preço + taxa fixa.
# - Frete: o mesmo da seção Anúncios (ship_cost do anúncio).
# - Faixa de preço (campanha do vendedor, DEAL, desconto próprio, relâmpago): usa o maior preço permitido (até o
#   valor máximo, se houver); se a margem passar da máxima, desce o preço até ela. Abaixo da margem mínima ou do
#   valor mínimo, a oferta não serve.
# - Cupom e desconto no Pix (BANK) somam ao preço e não entram na escolha.
module Painel
  class PromotionEvaluator
    PRICE_TYPES = %w[SELLER_CAMPAIGN DEAL PRICE_DISCOUNT LIGHTNING SMART SMART_LIGHTNING PRICE_MATCHING DOD
                     MARKETPLACE_CAMPAIGN UNHEALTHY_STOCK PRE_NEGOTIATED].freeze

    TYPE_LABELS = {
      "SELLER_CAMPAIGN" => "Campanha do vendedor", "DEAL" => "Evento do ML", "PRICE_DISCOUNT" => "Desconto próprio",
      "LIGHTNING" => "Oferta relâmpago", "SMART_LIGHTNING" => "Relâmpago com ML", "SMART" => "Desconto com ML",
      "PRICE_MATCHING" => "Preço competitivo", "DOD" => "Oferta do dia", "MARKETPLACE_CAMPAIGN" => "Campanha do ML",
      "UNHEALTHY_STOCK" => "Liquidação Full", "PRE_NEGOTIATED" => "Pré-negociada", "SELLER_COUPON_CAMPAIGN" => "Cupom",
      "BANK" => "Desconto no Pix", "VOLUME" => "Desconto por quantidade"
    }.freeze

    Rules = Struct.new(:min_pct, :max_pct, :min_price, :max_price, :tax_pct, :fixed_pct, :ads_unit, :price_cap, keyword_init: true)

    def initialize(item:, cost:, rules:)
      @item = item
      @cost = cost
      @rules = rules
      @ship = item.ship_cost.to_f
    end

    # => [ { offer:, price:, margin_pct:, profit:, valid:, reason:, as_is: }, ... ] para todas as ofertas do anúncio.
    # Oferta ativa entra como está (as_is, o preço de hoje) e, se for de faixa, também no preço da regra (editar o preço).
    def evaluate(offers)
      offers.flat_map do |offer|
        if offer.active? && offer.price.to_f.positive?
          as_is = evaluate_offer(offer, price: offer.price.to_f, as_is: true)
          offer.flexible? ? [ as_is, evaluate_offer(offer) ] : [ as_is ]
        else
          [ evaluate_offer(offer) ]
        end
      end
    end

    # A de maior margem entre as válidas. Empate: fica a atual (evita troca à toa), depois o desconto próprio (não
    # prende o anúncio à campanha de outro produto), depois a que termina mais tarde.
    def best(evaluated)
      evaluated.select { |e| e[:valid] }.max_by { |e| [ e[:margin_pct], tie_rank(e), e[:offer].finish_date.to_i ] }
    end

    def tie_rank(e)
      return 3 if e[:as_is]
      return 2 if e[:offer].active?
      return 1 if e[:offer].promotion_type == "PRICE_DISCOUNT"

      0
    end

    # Resultado sem promoção, no preço cheio do anúncio.
    def base(price)
      return nil if @cost.nil? || price.to_f <= 0

      economics(price.to_f, nil)
    end

    def evaluate_offer(offer, price: nil, as_is: false)
      out = { offer: offer, as_is: as_is, label: TYPE_LABELS.fetch(offer.promotion_type, offer.promotion_type.to_s.tr("_", " ").capitalize),
              price: nil, profit: nil, margin_pct: nil, meli_amount: 0.0, fee: nil, valid: false, reason: nil }
      return out.merge(reason: "não muda o preço (soma no checkout)") unless PRICE_TYPES.include?(offer.promotion_type)
      return out.merge(reason: "sem custo do produto") if @cost.nil?
      return out.merge(reason: "encerrada") if offer.finish_date.present? && offer.finish_date < Time.current

      price ||= choose_price(offer)
      return out.merge(reason: "sem preço permitido") if price.nil?

      eco = economics(price, offer)
      out = out.merge(eco)
      return out.merge(reason: "abaixo da margem mínima") if @rules.min_pct && eco[:margin_pct] < @rules.min_pct - 0.005
      return out.merge(reason: "acima da margem máxima") if @rules.max_pct && eco[:margin_pct] > @rules.max_pct + 0.005
      return out.merge(reason: "abaixo do valor mínimo") if @rules.min_price && price < @rules.min_price.to_f - 0.005
      return out.merge(reason: "acima do valor máximo") if @rules.max_price && price > @rules.max_price.to_f + 0.005
      return out.merge(reason: "acima do preço de venda de hoje") if @rules.price_cap && price > @rules.price_cap.to_f + 0.005

      out.merge(valid: true)
    end

    private

    def choose_price(offer)
      return (offer.price || offer.max_price)&.to_f unless offer.flexible?

      high = offer.max_price.to_f
      low = offer.min_price.to_f
      high = [ high, @rules.max_price.to_f ].min if @rules.max_price
      high = [ high, @rules.price_cap.to_f ].min if @rules.price_cap
      return nil unless high.positive? && high >= low
      return high if @rules.max_pct.nil? || economics(high, offer)[:margin_pct] <= @rules.max_pct

      target = price_for_margin(@rules.max_pct, offer)
      return high if target.nil?

      [ [ target, low ].max, high ].min.floor(2)
    end

    # Preço em que a margem dá exatamente `pct` (mesma faixa de tarifa do maior preço da oferta).
    def price_for_margin(pct, offer)
      fees = offer.fees || {}
      pct_fee = fees["percentage_fee"].to_f / 100.0
      fixed = fees["fixed_fee"].to_f + fees["financing"].to_f
      denominator = 1 - pct_fee - (@rules.tax_pct + @rules.fixed_pct + pct) / 100.0
      return nil if denominator <= 0

      (@cost + fixed + @ship + ads - meli_amount(offer)) / denominator
    end

    def economics(price, offer)
      meli = offer ? meli_amount(offer) : 0.0
      fee = fee_at(price, offer)
      tax = price * @rules.tax_pct / 100.0
      fixed = price * @rules.fixed_pct / 100.0
      profit = price + meli - @cost - fee - @ship - tax - fixed - ads
      { price: price.round(2), meli_amount: meli.round(2), fee: fee.round(2), profit: profit.round(2),
        margin_pct: (profit / price * 100.0).round(2),
        costs: { cost: @cost.round(2), fee: fee.round(2), shipping: @ship.round(2), tax: tax.round(2), fixed_expenses: fixed.round(2),
                 ads: ads.round(2), meli_amount: meli.round(2) } }
    end

    def ads = @rules.ads_unit.to_f

    def meli_amount(offer)
      return 0.0 unless offer.meli_percentage.to_f.positive?

      (offer.original_price || @item.price).to_f * offer.meli_percentage.to_f / 100.0
    end

    def fee_at(price, offer)
      fees = offer&.fees.presence || @item.fee_details.presence
      if offer&.fees.present? && (offer.fees["price"].to_f - price).abs < 0.005
        return offer.fees["sale_fee"].to_f
      end
      return @item.fee_now.to_f if fees.blank? || fees["percentage_fee"].nil?

      price * fees["percentage_fee"].to_f / 100.0 + fees["fixed_fee"].to_f + fees["financing"].to_f
    end
  end
end
