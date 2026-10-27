# Seção Promoções, fase 2: aplica no Mercado Livre a melhor oferta de um anúncio (ou a escolhida na tela) e sai de
# promoção. Cada ação relê as ofertas do anúncio antes (para não agir sobre dado velho), grava o histórico
# (ml_promotion_actions) e relê depois.
#
# Trocar = sair da promoção atual e entrar na nova; ajustar o preço = sair e entrar de novo na mesma com o preço da
# regra. Se a entrada falhar depois de sair, o Lunna tenta voltar para a promoção anterior com o preço de antes.
# Só ofertas que servem pela regra de margem são aplicadas; relâmpago e oferta do dia (pedem estoque reservado)
# ficam para o Mercado Livre.
module Painel
  class PromotionActions
    JOINABLE = %w[SELLER_CAMPAIGN DEAL PRICE_DISCOUNT SMART PRICE_MATCHING MARKETPLACE_CAMPAIGN UNHEALTHY_STOCK
                  SMART_LIGHTNING PRE_NEGOTIATED].freeze
    # Ofertas com preço dado pelo ML: entra-se pelo offer_id, sem escolher preço.
    OFFER_ID_TYPES = %w[SMART PRICE_MATCHING MARKETPLACE_CAMPAIGN UNHEALTHY_STOCK SMART_LIGHTNING PRE_NEGOTIATED].freeze
    PRICE_DISCOUNT_DAYS = 30

    Result = Struct.new(:ok, :message, :action, keyword_init: true)

    def self.apply(account, item_id, user: nil, source: "tela", target: nil)
      new(account, user, source).apply(item_id, target)
    end

    def self.leave(account, item_id, user: nil, source: "tela")
      new(account, user, source).leave(item_id)
    end

    def initialize(account, user, source)
      @account = account
      @user = user
      @source = source
    end

    # target: nil = a melhor oferta; ou { promotion_id:, promotion_type:, action: "aderir" | "editar_preco" }.
    def apply(item_id, target = nil)
      client = fresh_client
      Ml::Sync::Promotions.call(client, @account, item_ids: [ item_id ])
      ev = PromotionsQuery.evaluate_item(@account, item_id)
      current = ev[:current]
      chosen = target ? find_entry(ev[:evaluated], target) : ev[:best]

      return Result.new(ok: false, message: "Nenhuma oferta deste anúncio respeita a margem mínima.") if chosen.nil?
      return Result.new(ok: true, message: "O anúncio já está na melhor oferta.") if chosen[:as_is] || (current && chosen.equal?(current))
      return Result.new(ok: false, message: "Esta oferta não serve: #{chosen[:reason]}.") unless chosen[:valid]
      unless JOINABLE.include?(chosen[:offer].promotion_type)
        return Result.new(ok: false, message: "#{chosen[:label]} pede estoque reservado: entre por ela no Mercado Livre.")
      end

      kind = if current.nil? then "aderir"
      elsif current[:offer].promotion_id == chosen[:offer].promotion_id && current[:offer].promotion_type == chosen[:offer].promotion_type then "ajustar_preco"
      else "trocar"
      end
      execute(client, ev[:item], kind, current, chosen)
    rescue Ml::OAuth::Error
      Result.new(ok: false, message: "A conta do Mercado Livre precisa ser autorizada de novo.")
    end

    def leave(item_id)
      client = fresh_client
      Ml::Sync::Promotions.call(client, @account, item_ids: [ item_id ])
      ev = PromotionsQuery.evaluate_item(@account, item_id)
      current = ev[:current]
      return Result.new(ok: false, message: "O anúncio não está em nenhuma promoção de preço.") if current.nil?

      log = record("sair", ev[:item].item_id, current, nil)
      begin
        leave_offer(client, ev[:item].item_id, current[:offer])
        log.update!(ok: true)
        Result.new(ok: true, message: "Anúncio saiu de #{name_of(current)}.", action: log)
      rescue Ml::Client::Error => e
        log.update!(error: e.message.truncate(500))
        Result.new(ok: false, message: "O Mercado Livre recusou: #{ml_message(e)}", action: log)
      ensure
        Ml::Sync::Promotions.call(client, @account, item_ids: [ item_id ])
      end
    rescue Ml::OAuth::Error
      Result.new(ok: false, message: "A conta do Mercado Livre precisa ser autorizada de novo.")
    end

    private

    def fresh_client
      Ml::OAuth.refresh!(@account)
      Ml::Client.new(access_token: @account.access_token)
    end

    def find_entry(evaluated, target)
      action = target[:action].to_s
      evaluated.reject { |e| e[:as_is] }.find do |e|
        e[:offer].promotion_type == target[:promotion_type].to_s &&
          e[:offer].promotion_id.to_s == target[:promotion_id].to_s &&
          (action.empty? || (action == "editar_preco") == e[:offer].active?)
      end
    end

    def execute(client, item, kind, current, chosen)
      log = record(kind, item.item_id, current, chosen)
      if current
        begin
          leave_offer(client, item.item_id, current[:offer])
        rescue Ml::Client::Error => e
          return failed(log, "Não deu para sair de #{name_of(current)}: #{ml_message(e)}", e)
        end
      end

      begin
        client.join_promotion(item.item_id, join_body(chosen[:offer], chosen[:price]))
      rescue Ml::Client::Error => e
        back = current && rejoin(client, item.item_id, current)
        note = current ? (back ? " O anúncio voltou para #{name_of(current)}." : " Atenção: o anúncio ficou sem promoção.") : ""
        return failed(log, "O Mercado Livre recusou a entrada em #{name_of(chosen)}: #{ml_message(e)}.#{note}", e)
      end

      log.update!(ok: true)
      Result.new(ok: true, message: success_message(kind, current, chosen), action: log)
    ensure
      Ml::Sync::Promotions.call(client, @account, item_ids: [ item.item_id ])
    end

    def rejoin(client, item_id, current)
      client.join_promotion(item_id, join_body(current[:offer], current[:price]))
      true
    rescue Ml::Client::Error
      false
    end

    def leave_offer(client, item_id, offer)
      client.leave_promotion(item_id, promotion_type: offer.promotion_type,
        promotion_id: offer.promotion_type == "PRICE_DISCOUNT" ? nil : offer.promotion_id,
        offer_id: OFFER_ID_TYPES.include?(offer.promotion_type) ? offer_id(offer) : nil)
    end

    def join_body(offer, price)
      if OFFER_ID_TYPES.include?(offer.promotion_type)
        { promotion_id: offer.promotion_id, promotion_type: offer.promotion_type, offer_id: offer_id(offer) }
      elsif offer.promotion_type == "PRICE_DISCOUNT"
        now = Time.current.in_time_zone("America/Sao_Paulo")
        { promotion_type: "PRICE_DISCOUNT", deal_price: price.to_f.round(2),
          start_date: now.strftime("%Y-%m-%dT%H:%M:%S"), finish_date: (now + PRICE_DISCOUNT_DAYS.days).strftime("%Y-%m-%dT%H:%M:%S") }
      else
        { promotion_id: offer.promotion_id, promotion_type: offer.promotion_type, deal_price: price.to_f.round(2) }
      end
    end

    def offer_id(offer)
      (offer.payload || {})["offer_id"].presence || (offer.payload || {})["ref_id"]
    end

    def record(kind, item_id, from, to)
      @account.ml_promotion_actions.create!(
        item_id: item_id, kind: kind, source: @source, user: @user,
        from_promotion_id: from&.dig(:offer)&.promotion_id, from_type: from&.dig(:offer)&.promotion_type, from_name: from && name_of(from),
        from_price: from&.dig(:price), from_margin_pct: from&.dig(:margin_pct),
        to_promotion_id: to&.dig(:offer)&.promotion_id, to_type: to&.dig(:offer)&.promotion_type, to_name: to && name_of(to),
        to_price: to&.dig(:price), to_margin_pct: to&.dig(:margin_pct),
        gain: from && to ? (to[:profit] - from[:profit]).round(2) : nil
      )
    end

    def failed(log, message, error)
      log.update!(ok: false, error: error.message.truncate(500))
      Result.new(ok: false, message: message, action: log)
    end

    def name_of(entry) = entry[:offer].name.presence || entry[:label]

    def success_message(kind, current, chosen)
      price = ActiveSupport::NumberHelper.number_to_currency(chosen[:price], unit: "R$ ", separator: ",", delimiter: ".")
      case kind
      when "aderir" then "Anúncio entrou em #{name_of(chosen)} a #{price}."
      when "ajustar_preco" then "Preço em #{name_of(chosen)} ajustado para #{price}."
      else "Anúncio trocou #{name_of(current)} por #{name_of(chosen)} a #{price}."
      end
    end

    # Só a mensagem do ML, sem a URL interna.
    def ml_message(error) = error.message.split(" — ", 2).last.to_s.truncate(200)
  end
end
