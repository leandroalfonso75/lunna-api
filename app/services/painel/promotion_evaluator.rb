# Margem de cada oferta de promoção de um anúncio e a melhor delas (seção Promoções).
#
#   lucro antes do Ads = preço + parte do ML − custo − tarifa − frete − imposto − despesas fixas
#   lucro (pós Ads)    = lucro antes do Ads − Ads por unidade
#   margem = lucro ÷ preço (as duas são calculadas; a empresa escolhe qual vale para os limites: `basis`)
#
# - Ads: custo de Ads por unidade do anúncio nos últimos 15 dias (gasto ÷ unidades vendidas); sem histórico, zero.
# - Limites: por margem (mínima/máxima, %) ou por valor (preço mínimo/máximo, R$), um ou outro.
# - O preço cheio do anúncio nunca muda e é o teto (price_cap): a promoção parte dele e o preço final fica abaixo dele
#   (acima de R$ 79 o frete grátis é obrigatório e pago pelo vendedor; o preço cheio já define isso).
# - Parte do ML: nas ofertas com desconto dividido (meli_percentage), o ML banca esse % do preço original.
# - Tarifa: a do ML no preço da oferta (Ml::Sync::Promotions guarda em `fees`); fora desse preço,
#   % da tarifa × preço + taxa fixa.
# - Frete: o mesmo da seção Anúncios (ship_cost do anúncio).
# - Alvo (`target`): "min" = a margem mais perto da MÍNIMA (a máxima é só barreira); "max" = a mais perto da MÁXIMA (a
#   mínima é só piso). Melhor oferta = a de menor (ou maior) margem entre as que servem.
# - Faixa de preço (campanha do vendedor, DEAL, desconto próprio, relâmpago): o preço mais perto do alvo que respeita a
#   faixa do ML, os limites, a trava de lucro e o teto.
# - Aumento de preço (`allow_increase`): sem permissão, enquanto a promoção atual estiver valendo, nenhuma oferta pode
#   deixar o preço final acima do de hoje. Com permissão, pode subir, respeitada a margem máxima.
# - Oferta relâmpago (`allow_lightning`): só entra se a empresa autorizou, e dentro dos limites de margem como as demais.
# - Trava de lucro: quando a situação de hoje (promoção atual ou, sem promoção, o preço do anúncio) já está dentro dos
#   limites, uma oferta que reduz o lucro por unidade não serve. Se a empresa permite reduzir a margem
#   (allow_margin_drop), vale até a tolerância em pontos percentuais (margin_drop_tol).
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

    # basis: "after_ads" | "before_ads" (qual lucro vale para os limites); target: "min" | "max".
    Rules = Struct.new(:min_pct, :max_pct, :min_price, :max_price, :tax_pct, :fixed_pct, :ads_unit, :price_cap, :current_price,
                       :allow_margin_drop, :margin_drop_tol, :basis, :target, :allow_increase, :allow_lightning, keyword_init: true) do
      def before_ads? = basis.to_s == "before_ads"
      def target_max? = target.to_s == "max"
    end

    # Oferta relâmpago (cerca de 12 horas): só com autorização da empresa.
    FLASH_TYPES = %w[LIGHTNING SMART_LIGHTNING].freeze
    LIGHTNING_REASON = "oferta relâmpago não autorizada (Promoções > Autorizar a adesão de Oferta Relâmpago)".freeze

    # Promoção atual = a que define o preço que o comprador paga hoje (a de menor preço, se houver mais de uma ativa).
    # Programada (pending: o anúncio já entrou, mas ela ainda não começou) não define o preço de hoje.
    def self.current_of(evaluated)
      evaluated.select { |e| e[:as_is] && e[:offer].status == "started" && PRICE_TYPES.include?(e[:offer].promotion_type) }
        .min_by { |e| e[:price].to_f }
    end

    attr_reader :rules, :current, :baseline

    def initialize(item:, cost:, rules:)
      @item = item
      @cost = cost
      @rules = rules
      @ship = item.ship_cost.to_f
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

    # A margem que vale para os limites (antes ou pós Ads), de um resultado.
    def rule_margin(e) = @rules.before_ads? ? e[:margin_before_ads_pct] : e[:margin_pct]
    def rule_profit(e) = @rules.before_ads? ? e[:profit_before_ads] : e[:profit]

    # A mais perto do alvo (menor margem com alvo na mínima; maior, na máxima) entre as válidas, nesta ordem:
    #   1. campanhas do Mercado Livre (e a promoção atual, como está ou com o preço ajustado);
    #   2. só se nenhuma couber, o desconto próprio (PRICE_DISCOUNT, sem nome).
    # Campanha do vendedor (SELLER_CAMPAIGN, criada com nome na Central) não é escolhida para entrar: só pela tela.
    # Empate: fica a atual (evita troca à toa), depois a que já começou, depois a que termina mais tarde.
    def best(evaluated)
      # a programada (pending) já está garantida para depois: não é escolhida de novo
      valid = evaluated.select { |e| e[:valid] && e[:offer].status != "pending" }
      current_type = ->(e) { @current && e[:offer].promotion_id == @current[:offer].promotion_id && e[:offer].promotion_type == @current[:offer].promotion_type }
      eligible = valid.reject { |e| e[:offer].promotion_type == "SELLER_CAMPAIGN" && !e[:as_is] && !current_type.(e) }
      ml = eligible.reject { |e| e[:offer].promotion_type == "PRICE_DISCOUNT" && !e[:as_is] && !current_type.(e) }
      # empate: a atual, depois a que já começou (troca na hora), depois a que termina mais tarde
      later = ->(e) { e[:offer].start_date.present? && e[:offer].start_date > Time.current ? 1 : 0 }
      sign = @rules.target_max? ? -1 : 1
      (ml.presence || eligible).min_by { |e| [ sign * rule_margin(e).round(2), -tie_rank(e), later.(e), -e[:offer].finish_date.to_i ] }
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

    # relaxed: só os limites (margem, valor, preço cheio, faixa do ML), sem a trava de lucro nem a regra de aumento;
    # serve para achar a "oferta cabível" quando nenhuma passa com as regras todas. O que ela feriria vai em :soft_reason.
    def evaluate_offer(offer, price: nil, as_is: false, relaxed: false)
      out = { offer: offer, as_is: as_is, relaxed: relaxed, label: TYPE_LABELS.fetch(offer.promotion_type, offer.promotion_type.to_s.tr("_", " ").capitalize),
              price: nil, profit: nil, margin_pct: nil, profit_before_ads: nil, margin_before_ads_pct: nil, meli_amount: 0.0, fee: nil,
              valid: false, reason: nil }
      return out.merge(reason: "não muda o preço (soma no checkout)") unless PRICE_TYPES.include?(offer.promotion_type)
      return out.merge(reason: "sem custo do produto") if @cost.nil?
      return out.merge(reason: "encerrada") if offer.finish_date.present? && offer.finish_date < Time.current
      return out.merge(reason: LIGHTNING_REASON) if !as_is && FLASH_TYPES.include?(offer.promotion_type) && !@rules.allow_lightning
      if !as_is && (why = stock_reason(offer))
        return out.merge(reason: why)
      end

      price ||= choose_price(offer, relaxed: relaxed)
      return out.merge(reason: "sem preço permitido") if price.nil?

      eco = economics(price, offer)
      out = out.merge(eco)
      if (why = limit_reason(eco))
        return out.merge(reason: why)
      end
      if !as_is && (why = increase_reason(price) || guard_reason(eco))
        return relaxed ? out.merge(valid: true, soft_reason: why) : out.merge(reason: why)
      end

      out.merge(valid: true)
    end

    # A oferta que cabe nos limites quando nenhuma passa com as regras todas: campanhas do ML primeiro, depois o
    # desconto próprio; a mais perto do alvo. Pode ferir a trava de lucro ou a regra de aumento (:soft_reason).
    def fitting(offers)
      candidates = offers.select { |o| PRICE_TYPES.include?(o.promotion_type) && o.status != "pending" && o.promotion_type != "SELLER_CAMPAIGN" }
      evaluated = candidates.map { |o| evaluate_offer(o, relaxed: true) }.select { |e| e[:valid] }
      ml = evaluated.reject { |e| e[:offer].promotion_type == "PRICE_DISCOUNT" }
      sign = @rules.target_max? ? -1 : 1
      (ml.presence || evaluated).min_by { |e| [ sign * rule_margin(e).round(2), e[:soft_reason] ? 1 : 0, -e[:offer].finish_date.to_i ] }
    end

    private

    # A regra de limite que o resultado fere (margem, valor, preço cheio), ou nil.
    def limit_reason(eco)
      price = eco[:price]
      margin = rule_margin(eco)
      return "abaixo da margem mínima" if @rules.min_pct && margin < @rules.min_pct - 0.005
      return "acima da margem máxima" if @rules.max_pct && margin > @rules.max_pct + 0.005
      return "abaixo do valor mínimo" if @rules.min_price && price < @rules.min_price.to_f - 0.005
      return "acima do valor máximo" if @rules.max_price && price > @rules.max_price.to_f + 0.005
      return "acima do preço cheio do anúncio" if @rules.price_cap && price > @rules.price_cap.to_f + 0.005

      nil
    end

    # Sem permissão de aumento, o preço final não sobe enquanto a promoção atual estiver valendo.
    def increase_reason(price)
      return nil if @rules.allow_increase || @current.nil?
      return nil if price <= @current[:price].to_f + 0.005

      format("aumentaria o preço de R$ %.2f para R$ %.2f (aumento não permitido enquanto a promoção atual não acabar)", @current[:price], price).tr(".", ",")
    end

    # Hoje: a promoção atual ou, sem ela, o preço do anúncio. Dentro dos limites, vira a trava de lucro (@guard).
    def set_baseline(current)
      @current = current
      @baseline = current || (@cost && base((@rules.current_price || @rules.price_cap).to_f))
      ok = if current then current[:valid]
      elsif @baseline then limit_reason(@baseline).nil?
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
        return nil if rule_margin(eco) >= rule_margin(@guard) - tol - 0.005

        format("reduziria a margem de %.1f%% para %.1f%% (tolerância de %g p.p.)", rule_margin(@guard), rule_margin(eco), tol)
      else
        return nil if rule_profit(eco) >= rule_profit(@guard) - 0.005

        format("reduziria o lucro de R$ %.2f para R$ %.2f por unidade", rule_profit(@guard), rule_profit(eco)).tr(".", ",")
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

    # Faixa: o preço mais perto do alvo. Teto = faixa do ML, valor máximo, preço cheio, margem máxima e, sem permissão de
    # aumento, o preço de hoje. Piso = faixa do ML, valor mínimo, margem mínima e a trava de lucro. Alvo na mínima: fica
    # no piso; alvo na máxima: fica no teto. Se o piso passa do teto, fica no teto e a regra ferida aparece no motivo.
    def choose_price(offer, relaxed: false)
      return (offer.price || offer.max_price)&.to_f unless offer.flexible?

      high = [ offer.max_price.to_f, @rules.max_price&.to_f, @rules.price_cap&.to_f ].compact.min
      high = [ high, @current[:price].to_f ].min if !@rules.allow_increase && @current && !relaxed
      if @rules.max_pct && (top = price_for_margin(@rules.max_pct, offer))
        high = [ high, top.floor(2) ].min
      end
      # relâmpago: o ML recusa preço acima do que ele indica em `price` ("discounted price is not credible")
      credible = (offer.payload || {})["price"].to_f
      high = [ high, credible ].min if FLASH_TYPES.include?(offer.promotion_type) && credible.positive?
      return nil unless high.positive?

      floors = [ offer.min_price.to_f, @rules.min_price.to_f ]
      floors << price_for_margin(@rules.min_pct, offer) if @rules.min_pct
      if @guard && !relaxed
        floors << if @rules.allow_margin_drop
          price_for_margin(rule_margin(@guard) - @rules.margin_drop_tol.to_f, offer)
        else
          price_for_profit(rule_profit(@guard), offer)
        end
      end
      low = (floors.compact.max - 1e-9).ceil(2)
      # o arredondamento a centavos pode deixar a margem um centésimo abaixo da mínima: sobe um centavo se for o caso
      low += 0.01 if @rules.min_pct && low <= high && rule_margin(economics(low, offer)) < @rules.min_pct
      chosen = @rules.target_max? ? high : [ low, high ].min
      [ chosen, offer.min_price.to_f ].max.round(2)
    end

    # Ads que entra na conta dos limites (zero quando a base é o lucro antes do Ads).
    def rule_ads = @rules.before_ads? ? 0.0 : ads

    # Preço em que o lucro (na base dos limites) dá exatamente `profit` (mesma faixa de tarifa do maior preço da oferta).
    def price_for_profit(profit, offer)
      fees = offer.fees || {}
      denominator = 1 - fees["percentage_fee"].to_f / 100.0 - (@rules.tax_pct + @rules.fixed_pct) / 100.0
      return nil if denominator <= 0

      (profit + @cost + fees["fixed_fee"].to_f + fees["financing"].to_f + @ship + rule_ads - meli_amount(offer)) / denominator
    end

    # Preço em que a margem (na base dos limites) dá exatamente `pct` (mesma faixa de tarifa do maior preço da oferta).
    def price_for_margin(pct, offer)
      fees = offer.fees || {}
      pct_fee = fees["percentage_fee"].to_f / 100.0
      fixed = fees["fixed_fee"].to_f + fees["financing"].to_f
      denominator = 1 - pct_fee - (@rules.tax_pct + @rules.fixed_pct + pct) / 100.0
      return nil if denominator <= 0

      (@cost + fixed + @ship + rule_ads - meli_amount(offer)) / denominator
    end

    def economics(price, offer)
      meli = offer ? meli_amount(offer) : 0.0
      fee = fee_at(price, offer)
      tax = price * @rules.tax_pct / 100.0
      fixed = price * @rules.fixed_pct / 100.0
      before = price + meli - @cost - fee - @ship - tax - fixed
      profit = before - ads
      { price: price.round(2), meli_amount: meli.round(2), fee: fee.round(2),
        profit: profit.round(2), margin_pct: (profit / price * 100.0).round(2),
        profit_before_ads: before.round(2), margin_before_ads_pct: (before / price * 100.0).round(2),
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
