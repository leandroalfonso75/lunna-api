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
# - Objetivo: a margem mais perto da MÍNIMA. A máxima é só uma barreira (nenhuma oferta passa dela), exceto na oferta
#   relâmpago (dura cerca de 12 horas). Melhor oferta = a de menor margem entre as que servem.
# - Faixa de preço (campanha do vendedor, DEAL, desconto próprio, relâmpago): o menor preço permitido que ainda dá a
#   margem mínima (e respeita o valor mínimo, a faixa do ML e a trava de lucro abaixo), limitado pelo teto.
# - Trava de lucro: quando a situação de hoje (promoção atual ou, sem promoção, o preço do anúncio) já está dentro dos
#   limites, uma oferta que reduz o lucro por unidade não serve. Se a empresa permite reduzir a margem
#   (promo_allow_margin_drop), vale até a tolerância em pontos percentuais (promo_margin_drop_tolerance).
#   Fora dos limites (abaixo da mínima, acima da máxima), não há trava: a regra manda mudar.
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

    Rules = Struct.new(:min_pct, :max_pct, :min_price, :max_price, :tax_pct, :fixed_pct, :ads_unit, :price_cap, :current_price,
                       :allow_margin_drop, :margin_drop_tol, keyword_init: true)

    # Oferta relâmpago: curta (cerca de 12 horas), fica fora da barreira da margem máxima.
    FLASH_TYPES = %w[LIGHTNING SMART_LIGHTNING].freeze

    # Promoção atual = a que define o preço que o comprador paga hoje (a de menor preço, se houver mais de uma ativa).
    def self.current_of(evaluated)
      evaluated.select { |e| e[:as_is] && PRICE_TYPES.include?(e[:offer].promotion_type) }
        .min_by { |e| [ e[:offer].status == "started" ? 0 : 1, e[:price].to_f ] }
    end

    # Faixas de aumento permitido sobre a última promoção: [preço mínimo da faixa, % máximo].
    RAISE_BANDS = [ [ 200.0, 2.0 ], [ 100.0, 3.0 ], [ 50.0, 5.0 ], [ 0.0, 7.0 ] ].freeze

    def self.raise_pct_for(price)
      RAISE_BANDS.find { |floor, _| price >= floor }&.last
    end

    attr_reader :rules, :current, :baseline

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
      as_is = offers.each_with_index.select { |o, _| o.active? && o.price.to_f.positive? }
        .to_h { |o, i| [ i, evaluate_offer(o, price: o.price.to_f, as_is: true) ] }
      set_baseline(self.class.current_of(as_is.values))
      offers.each_with_index.flat_map do |offer, i|
        if (e = as_is[i])
          offer.flexible? ? [ e, evaluate_offer(offer) ] : [ e ]
        else
          [ evaluate_offer(offer) ]
        end
      end
    end

    # A situação de hoje (promoção atual ou, sem ela, o preço do anúncio) está dentro dos limites?
    def baseline_valid? = !@guard.nil?

    # A de MENOR margem entre as válidas (a mais perto da mínima), nesta ordem de preferência:
    #   1. campanhas do Mercado Livre (e a promoção atual, como está ou com o preço ajustado);
    #   2. só se nenhuma couber, o desconto próprio (PRICE_DISCOUNT, sem nome).
    # Campanha do vendedor (SELLER_CAMPAIGN, criada com nome na Central) não é escolhida para entrar: só pela tela.
    # Empate: fica a atual (evita troca à toa), depois a que termina mais tarde.
    def best(evaluated)
      valid = evaluated.select { |e| e[:valid] }
      current_type = ->(e) { @current && e[:offer].promotion_id == @current[:offer].promotion_id && e[:offer].promotion_type == @current[:offer].promotion_type }
      eligible = valid.reject { |e| e[:offer].promotion_type == "SELLER_CAMPAIGN" && !e[:as_is] && !current_type.(e) }
      ml = eligible.reject { |e| e[:offer].promotion_type == "PRICE_DISCOUNT" && !e[:as_is] && !current_type.(e) }
      (ml.presence || eligible).min_by { |e| [ e[:margin_pct].round(2), -tie_rank(e), -e[:offer].finish_date.to_i ] }
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
      if !as_is && (why = stock_reason(offer))
        return out.merge(reason: why)
      end

      price ||= choose_price(offer)
      return out.merge(reason: "sem preço permitido") if price.nil?

      eco = economics(price, offer)
      out = out.merge(eco)
      if (why = limit_reason(eco, offer))
        return out.merge(reason: why)
      end
      if !as_is && (why = raise_reason(price) || guard_reason(eco))
        return out.merge(reason: why)
      end

      out.merge(valid: true)
    end

    private

    # A regra de limite que o resultado fere (margem, valor, preço cheio), ou nil.
    def limit_reason(eco, offer)
      price = eco[:price]
      return "abaixo da margem mínima" if @rules.min_pct && eco[:margin_pct] < @rules.min_pct - 0.005
      if @rules.max_pct && eco[:margin_pct] > @rules.max_pct + 0.005 && !(offer && FLASH_TYPES.include?(offer.promotion_type))
        return "acima da margem máxima"
      end
      return "abaixo do valor mínimo" if @rules.min_price && price < @rules.min_price.to_f - 0.005
      return "acima do valor máximo" if @rules.max_price && price > @rules.max_price.to_f + 0.005
      return "acima do preço cheio do anúncio" if @rules.price_cap && price > @rules.price_cap.to_f + 0.005

      nil
    end

    # Hoje: a promoção atual ou, sem ela, o preço do anúncio. Dentro dos limites, vira a trava de lucro (@guard).
    def set_baseline(current)
      @current = current
      @baseline = current || (@cost && base((@rules.current_price || @rules.price_cap).to_f))
      ok = if current then current[:valid]
      elsif @baseline then limit_reason(@baseline, nil).nil?
      else false
      end
      @guard = ok ? @baseline : nil
    end

    # Trava de lucro: sem permissão, nenhuma troca pode reduzir o lucro por unidade; com permissão, a margem pode cair
    # até a tolerância (pontos percentuais).
    def guard_reason(eco)
      return nil if @guard.nil?

      if @rules.allow_margin_drop
        tol = @rules.margin_drop_tol.to_f
        return nil if eco[:margin_pct] >= @guard[:margin_pct] - tol - 0.005

        format("reduziria a margem de %.1f%% para %.1f%% (tolerância de %g p.p.)", @guard[:margin_pct], eco[:margin_pct], tol)
      else
        return nil if eco[:profit] >= @guard[:profit] - 0.005

        format("reduziria o lucro de R$ %.2f para R$ %.2f por unidade", @guard[:profit], eco[:profit]).tr(".", ",")
      end
    end

    # Relâmpago e oferta do dia: o anúncio precisa ter o estoque que o ML sugere reservar.
    def stock_reason(offer)
      return nil unless MlPromotionOffer::STOCK_TYPES.include?(offer.promotion_type)

      need = offer.stock_reserved
      return "sem estoque sugerido pelo ML para reservar" if need.nil? || need <= 0

      have = @item.try(:available_quantity).to_i
      return "estoque insuficiente para reservar (pede #{need}, tem #{have})" if have < need

      nil
    end

    # Faixa: o menor preço que ainda dá a margem mínima (e o valor mínimo, a faixa do ML e a trava de lucro), sem passar
    # do teto (valor máximo, preço cheio, limite de aumento e, fora do relâmpago, a margem máxima). Se nem o teto
    # alcança o piso, fica no teto e a regra ferida aparece no motivo.
    def choose_price(offer)
      return (offer.price || offer.max_price)&.to_f unless offer.flexible?

      high = [ offer.max_price.to_f, @rules.max_price&.to_f, @rules.price_cap&.to_f, @raise&.dig(:cap) ].compact.min
      if @rules.max_pct && !FLASH_TYPES.include?(offer.promotion_type) && (top = price_for_margin(@rules.max_pct, offer))
        high = [ high, top.floor(2) ].min
      end
      # relâmpago: o ML recusa preço acima do que ele indica em `price` ("discounted price is not credible")
      credible = (offer.payload || {})["price"].to_f
      high = [ high, credible ].min if FLASH_TYPES.include?(offer.promotion_type) && credible.positive?
      return nil unless high.positive?

      floors = [ offer.min_price.to_f, @rules.min_price.to_f ]
      floors << price_for_margin(@rules.min_pct, offer) if @rules.min_pct
      if @guard
        floors << if @rules.allow_margin_drop
          price_for_margin(@guard[:margin_pct] - @rules.margin_drop_tol.to_f, offer)
        else
          price_for_profit(@guard[:profit], offer)
        end
      end
      low = (floors.compact.max - 1e-9).ceil(2)
      [ [ low, high ].min, offer.min_price.to_f ].max.round(2)
    end

    # Preço em que o lucro por unidade dá exatamente `profit` (mesma faixa de tarifa do maior preço da oferta).
    def price_for_profit(profit, offer)
      fees = offer.fees || {}
      denominator = 1 - fees["percentage_fee"].to_f / 100.0 - (@rules.tax_pct + @rules.fixed_pct) / 100.0
      return nil if denominator <= 0

      (profit + @cost + fees["fixed_fee"].to_f + fees["financing"].to_f + @ship + ads - meli_amount(offer)) / denominator
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
