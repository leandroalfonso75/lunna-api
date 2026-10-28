# Margem de cada oferta de promoção de um anúncio e a melhor delas (seção Promoções).
#
#   lucro (pós Ads) = preço + parte do ML − custo − tarifa − frete − imposto − despesas fixas − Ads
#   margem = lucro ÷ preço
#
# - Ads: custo de Ads por unidade do anúncio nos últimos 15 dias (gasto ÷ unidades vendidas); sem histórico, zero.
# - Limites: por margem (mínima/máxima, %) ou por valor (preço mínimo/máximo, R$), um ou outro.
# - Aumento do preço de venda limitado por faixa, em relação à última promoção (current_price): acima de R$ 200 até 2%,
#   de R$ 100 a R$ 199,99 até 3%, de R$ 50 a R$ 99,99 até 5%, de R$ 10 a R$ 49,99 até 7% (abaixo de R$ 10 também 7%).
#   Mesmo dentro do limite, o preço não passa para a casa de cem seguinte (198 não vira 201: fica em 199,99).
# - O preço cheio do anúncio nunca muda e é o teto (price_cap): a promoção parte dele e o preço final fica abaixo dele
#   (acima de R$ 79 o frete grátis é obrigatório e pago pelo vendedor; o preço cheio já define isso).
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
    # Relâmpago e oferta do dia pedem estoque reservado: o Lunna não entra nelas (só pelo ML), então não são escolhidas.
    STOCK_RESERVED_TYPES = %w[LIGHTNING DOD].freeze

    TYPE_LABELS = {
      "SELLER_CAMPAIGN" => "Campanha do vendedor", "DEAL" => "Evento do ML", "PRICE_DISCOUNT" => "Desconto próprio",
      "LIGHTNING" => "Oferta relâmpago", "SMART_LIGHTNING" => "Relâmpago com ML", "SMART" => "Desconto com ML",
      "PRICE_MATCHING" => "Preço competitivo", "DOD" => "Oferta do dia", "MARKETPLACE_CAMPAIGN" => "Campanha do ML",
      "UNHEALTHY_STOCK" => "Liquidação Full", "PRE_NEGOTIATED" => "Pré-negociada", "SELLER_COUPON_CAMPAIGN" => "Cupom",
      "BANK" => "Desconto no Pix", "VOLUME" => "Desconto por quantidade"
    }.freeze

    Rules = Struct.new(:min_pct, :max_pct, :min_price, :max_price, :tax_pct, :fixed_pct, :ads_unit, :price_cap, :current_price,
                       keyword_init: true)

    # Faixas de aumento permitido sobre a última promoção: [preço mínimo da faixa, % máximo].
    RAISE_BANDS = [ [ 200.0, 2.0 ], [ 100.0, 3.0 ], [ 50.0, 5.0 ], [ 0.0, 7.0 ] ].freeze

    def self.raise_pct_for(price)
      RAISE_BANDS.find { |floor, _| price >= floor }&.last
    end

    attr_reader :rules

    def initialize(item:, cost:, rules:)
      @item = item
      @cost = cost
      @rules = rules
      @ship = item.ship_cost.to_f
      @raise = raise_limits(rules.current_price&.to_f)
    end

    # => { cap:, pct:, hundred: } ou nil sem preço atual. `cap` = maior preço permitido ao subir; `hundred` = casa de
    # cem que o aumento não pode cruzar (nil quando o limite de % já fica abaixo dela).
    def raise_limits(current)
      return nil unless current&.positive?

      pct = self.class.raise_pct_for(current)
      cap = (current * (1 + pct / 100.0)).floor(2)
      hundred = (current / 100).floor * 100 + 100
      crosses = current < hundred && cap >= hundred
      { cap: crosses ? (hundred - 0.01).round(2) : cap, pct: pct, hundred: crosses ? hundred : nil, current: current }
    end

    def raise_reason(price)
      return nil if @raise.nil? || price <= @raise[:cap] + 0.005
      return "passaria da casa dos R$ #{@raise[:hundred].to_i}" if @raise[:hundred] && price >= @raise[:hundred]

      format("aumento acima de %g%% sobre a última promoção (R$ %.2f)", @raise[:pct], @raise[:current])
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
      return out.merge(reason: "pede estoque reservado (entrar pelo ML)") if !as_is && STOCK_RESERVED_TYPES.include?(offer.promotion_type)

      price ||= choose_price(offer)
      return out.merge(reason: "sem preço permitido") if price.nil?

      eco = economics(price, offer)
      out = out.merge(eco)
      return out.merge(reason: "abaixo da margem mínima") if @rules.min_pct && eco[:margin_pct] < @rules.min_pct - 0.005
      return out.merge(reason: "acima da margem máxima") if @rules.max_pct && eco[:margin_pct] > @rules.max_pct + 0.005
      return out.merge(reason: "abaixo do valor mínimo") if @rules.min_price && price < @rules.min_price.to_f - 0.005
      return out.merge(reason: "acima do valor máximo") if @rules.max_price && price > @rules.max_price.to_f + 0.005
      return out.merge(reason: "acima do preço cheio do anúncio") if @rules.price_cap && price > @rules.price_cap.to_f + 0.005
      if !as_is && (why = raise_reason(price))
        return out.merge(reason: why)
      end

      out.merge(valid: true)
    end

    private

    def choose_price(offer)
      return (offer.price || offer.max_price)&.to_f unless offer.flexible?

      high = offer.max_price.to_f
      low = offer.min_price.to_f
      high = [ high, @rules.max_price.to_f ].min if @rules.max_price
      high = [ high, @rules.price_cap.to_f ].min if @rules.price_cap
      high = [ high, @raise[:cap] ].min if @raise
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
