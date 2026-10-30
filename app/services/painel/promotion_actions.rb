# Seção Promoções, fase 2: aplica no Mercado Livre a melhor oferta de um anúncio (ou a escolhida na tela) e sai de
# promoção. Cada ação relê as ofertas do anúncio antes (para não agir sobre dado velho), grava o histórico
# (ml_promotion_actions) e relê depois.
#
# Trocar = sair da promoção atual e entrar na nova; ajustar o preço = sair e entrar de novo na mesma com o preço da
# regra. Se a entrada falhar depois de sair, o Lunna tenta voltar para a promoção anterior com o preço de antes.
# Só ofertas que servem pela regra de margem são aplicadas. Relâmpago e oferta do dia entram reservando o estoque
# sugerido pelo ML (stock.min da oferta). Anúncio marcado como "não automatizar" só muda por ação da tela, uma a uma.
module Painel
  class PromotionActions
    JOINABLE = %w[SELLER_CAMPAIGN DEAL PRICE_DISCOUNT SMART PRICE_MATCHING MARKETPLACE_CAMPAIGN UNHEALTHY_STOCK LIGHTNING DOD
                  SMART_LIGHTNING PRE_NEGOTIATED].freeze
    # Ofertas com preço dado pelo ML: entra-se pelo offer_id, sem escolher preço.
    OFFER_ID_TYPES = %w[SMART PRICE_MATCHING MARKETPLACE_CAMPAIGN UNHEALTHY_STOCK SMART_LIGHTNING PRE_NEGOTIATED].freeze
    PRICE_DISCOUNT_DAYS = 30

    Result = Struct.new(:ok, :message, :action, keyword_init: true)

    def self.apply(account, item_id, user: nil, source: "tela", target: nil, run: nil)
      new(account, user, source, run: run).apply(item_id, target)
    end

    # Leva a mesma promoção para os outros anúncios do mesmo SKU e/ou das outras variações do produto, em fila
    # (Ml::PromotionsApplyJob): cada um é avaliado pelo seu preço e pelos seus limites; o que não servir fica no
    # histórico com o motivo. => quantidade enviada para a fila.
    def self.extend_to_related(account, item_id, target, user: nil, sku: false, variations: false)
      return 0 if target.blank? || target[:promotion_type].blank? || !(sku || variations)

      item = account.ml_items.find(item_id)
      ids = []
      ids += account.ml_items.where(sku: item.sku, status: "active").where.not(item_id: item.item_id).pluck(:item_id) if sku && item.sku.present?
      # variações: só o anúncio equivalente de cada outra variação; com o SKU junto, todos os anúncios delas
      ids += (sku ? PromotionSettings.variation_item_ids(account, item) : PromotionSettings.counterpart_item_ids(account, item)) if variations
      ids = account.ml_items.where(item_id: ids.uniq, status: "active").pluck(:item_id)
      ids -= account.ml_promotion_settings.where(item_id: ids, automation_enabled: false).pluck(:item_id) # "não automatizar"
      return 0 if ids.empty?

      # com force ("mesmo assim" / "cabível"), cada anúncio entra no preço que cabe nos limites dele
      Ml::PromotionsApplyJob.perform_later(account.id, ids, user&.id, target.slice(:promotion_id, :promotion_type, :force).transform_keys(&:to_s))
      ids.size
    end

    def self.leave(account, item_id, user: nil, source: "tela")
      new(account, user, source).leave(item_id)
    end

    def initialize(account, user, source, run: nil)
      @account = account
      @user = user
      @source = source
      @run = run
    end

    # target: nil = a melhor oferta; ou { promotion_id:, promotion_type:, action: "aderir" | "editar_preco" }.
    # Com price: aplica nesse preço (só ofertas de preço livre, dentro da faixa do ML). Com force: aplica mesmo
    # ferindo as regras do Lunna (margem, valor, aumento) e guarda no Histórico a regra ferida.
    def apply(item_id, target = nil)
      client = fresh_client
      Ml::Sync::Promotions.call(client, @account, item_ids: [ item_id ])
      ev = PromotionsQuery.evaluate_item(@account, item_id)
      current = ev[:current]
      chosen = target ? find_entry(ev[:evaluated], target) : ev[:best]
      force = target && ActiveModel::Type::Boolean.new.cast(target[:force])

      return Result.new(ok: false, message: "Nenhuma oferta deste anúncio respeita a margem mínima.") if chosen.nil?
      if target && target[:price].present?
        price = target[:price].to_s.tr(",", ".").to_f.round(2)
        if (why = custom_price_problem(chosen[:offer], price, ev[:evaluator]))
          return Result.new(ok: false, message: why)
        end
        chosen = ev[:evaluator].evaluate_offer(chosen[:offer], price: price)
      end
      return Result.new(ok: true, message: "O anúncio já está na melhor oferta.") if chosen[:as_is] || (current && chosen.equal?(current))
      if force && !chosen[:valid] && target[:price].blank?
        # "mesmo assim" sem preço informado: prefere o preço que cabe nos limites (ferindo só a trava de lucro ou o aumento)
        relaxed = ev[:evaluator].evaluate_offer(chosen[:offer], relaxed: true)
        chosen = relaxed.merge(valid: false, reason: relaxed[:soft_reason]) if relaxed[:valid] && relaxed[:soft_reason]
      end
      unless chosen[:valid] || (force && !HARD_REASONS.any? { |r| chosen[:reason].to_s.start_with?(r) })
        return Result.new(ok: false, message: "Esta oferta não serve: #{chosen[:reason]}.")
      end
      @forced_reason = chosen[:valid] ? nil : chosen[:reason]
      unless JOINABLE.include?(chosen[:offer].promotion_type)
        return Result.new(ok: false, message: "#{chosen[:label]} não pode ser aplicada pelo Lunna: entre por ela no Mercado Livre.")
      end

      kind = self.class.kind_for(@account, current, chosen)
      return schedule(client, ev[:item], current, chosen) if kind == "agendar"

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

    # aderir | ajustar_preco | trocar | agendar. Agendar = a promoção atual está valendo e a nova só começa depois: o
    # anúncio continua na atual, entra na nova (que começa sozinha) e sai da atual quando a nova começar.
    def self.kind_for(account, current, chosen)
      return "aderir" if current.nil?
      return "ajustar_preco" if current[:offer].promotion_id == chosen[:offer].promotion_id && current[:offer].promotion_type == chosen[:offer].promotion_type

      start = start_of(account, chosen[:offer])
      current[:offer].status == "started" && start && start > Time.current + 1.minute ? "agendar" : "trocar"
    end

    # Início da oferta: o da oferta do anúncio ou, sem ele, o da campanha.
    def self.start_of(account, offer)
      offer.start_date || account.ml_promotions.where(promotion_id: offer.promotion_id).pick(:start_date)
    end

    # Depois que a nova promoção começou: sai da anterior (Ml::PromotionsHandoffJob).
    def handoff(item_id, from_target, to_target)
      client = fresh_client
      Ml::Sync::Promotions.call(client, @account, item_ids: [ item_id ])
      offers = @account.ml_promotion_offers.where(item_id: item_id)
      started = ->(t) { offers.find_by(promotion_id: t[:promotion_id].presence, promotion_type: t[:promotion_type], status: "started") }
      to = started.(to_target)
      from = started.(from_target)
      return Result.new(ok: false, message: "A nova promoção ainda não começou para este anúncio.") unless to
      return Result.new(ok: true, message: "O anúncio já tinha saído da promoção anterior.") unless from

      ev = PromotionsQuery.evaluate_item(@account, item_id)
      entry = ev[:evaluated].find { |e| e[:as_is] && e[:offer] == from }
      log = record("sair", item_id, entry, nil)
      leave_offer(client, item_id, from)
      log.update!(ok: true, error: "saiu ao começar #{to.name.presence || to.promotion_type}")
      Result.new(ok: true, message: "Saiu de #{from.name.presence || from.promotion_type}: a nova promoção começou.", action: log)
    rescue Ml::Client::Error => e
      log&.update!(error: e.message.truncate(500))
      Result.new(ok: false, message: "O Mercado Livre recusou: #{ml_message(e)}", action: log)
    end

    private

    # Entra na nova sem sair da atual; se a atual ainda vale quando a nova começa, sai dela nessa hora.
    def schedule(client, item, current, chosen)
      start = self.class.start_of(@account, chosen[:offer])
      log = record("agendar", item.item_id, current, chosen)
      begin
        client.join_promotion(item.item_id, join_body(chosen[:offer], chosen[:price]))
      rescue Ml::Client::Error => e
        return failed(log, "O Mercado Livre recusou a entrada em #{name_of(chosen)}: #{ml_message(e)}. O anúncio segue em #{name_of(current)}.", e)
      end
      log.update!(ok: true)
      finish = current[:offer].finish_date
      overlap = finish.nil? || finish > start
      if overlap
        target = ->(o) { { promotion_id: o.promotion_id.to_s, promotion_type: o.promotion_type } }
        Ml::PromotionsHandoffJob.set(wait_until: start + 5.minutes)
          .perform_later(@account.id, item.item_id, target.(current[:offer]), target.(chosen[:offer]), @source)
      end
      when_text = start.in_time_zone("America/Sao_Paulo").strftime("%d/%m %H:%M")
      Result.new(ok: true, action: log,
        message: "Anúncio entrou em #{name_of(chosen)}, que começa em #{when_text}; até lá segue em #{name_of(current)}" +
                 (overlap ? ", e sai dela quando a nova começar." : "."))
    ensure
      Ml::Sync::Promotions.call(client, @account, item_ids: [ item.item_id ])
    end

    # Entrou numa promoção enquanto o anúncio já tem outra programada (pending, ex.: Black Friday): sai desta quando a
    # programada começar.
    def handoff_to_scheduled(item, chosen)
      scheduled = @account.ml_promotion_offers.where(item_id: item.item_id, status: "pending")
        .reject { |o| o.promotion_id == chosen[:offer].promotion_id && o.promotion_type == chosen[:offer].promotion_type }
        .filter_map { |o| (start = self.class.start_of(@account, o)) && start > Time.current ? [ o, start ] : nil }
        .min_by(&:last)
      return unless scheduled

      target = ->(o) { { promotion_id: o.promotion_id.to_s, promotion_type: o.promotion_type } }
      Ml::PromotionsHandoffJob.set(wait_until: scheduled.last + 5.minutes)
        .perform_later(@account.id, item.item_id, target.(chosen[:offer]), target.(scheduled.first), @source)
    end

    def fresh_client
      Ml::OAuth.refresh!(@account)
      Ml::Client.new(access_token: @account.access_token)
    end

    # O que nem "aplicar mesmo assim" passa: o Mercado Livre recusaria (ou não há o que aplicar).
    HARD_REASONS = [ "não muda o preço", "encerrada", "sem preço permitido", "acima do preço cheio do anúncio",
                     "sem estoque sugerido", "estoque insuficiente" ].freeze

    def custom_price_problem(offer, price, evaluator)
      brl = ->(v) { ActiveSupport::NumberHelper.number_to_currency(v, unit: "R$", separator: ",", delimiter: ".") }
      return "Informe um preço maior que zero." unless price.positive?
      return "#{offer.name.presence || offer.promotion_type} tem preço fixo dado pelo Mercado Livre: não dá para escolher outro valor." unless offer.flexible?
      return "O Mercado Livre só aceita até #{brl.(offer.max_price)} nesta oferta." if price > offer.max_price.to_f + 0.005
      return "O Mercado Livre só aceita a partir de #{brl.(offer.min_price)} nesta oferta." if offer.min_price.to_f.positive? && price < offer.min_price.to_f - 0.005
      cap = evaluator.rules.price_cap
      return "O preço precisa ficar abaixo do preço cheio do anúncio (#{brl.(cap)})." if cap && price > cap.to_f + 0.005

      nil
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
      handoff_to_scheduled(item, chosen)
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
      body = base_join_body(offer, price)
      body[:stock] = offer.stock_reserved if offer.stock_reserved
      body
    end

    def base_join_body(offer, price)
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
        item_id: item_id, kind: kind, source: @source, user: @user, run: @run,
        from_profit: from&.dig(:profit), to_profit: to&.dig(:profit),
        from_promotion_id: from&.dig(:offer)&.promotion_id, from_type: from&.dig(:offer)&.promotion_type, from_name: from && name_of(from),
        from_price: from&.dig(:price), from_margin_pct: from&.dig(:margin_pct),
        to_promotion_id: to&.dig(:offer)&.promotion_id, to_type: to&.dig(:offer)&.promotion_type, to_name: to && name_of(to),
        to_price: to&.dig(:price), to_margin_pct: to&.dig(:margin_pct),
        gain: from && to ? (to[:profit] - from[:profit]).round(2) : nil,
        forced_reason: to ? @forced_reason : nil
      )
    end

    def failed(log, message, error)
      log.update!(ok: false, error: error.message.truncate(500))
      Result.new(ok: false, message: message, action: log)
    end

    def name_of(entry) = entry[:offer].name.presence || entry[:label]

    def success_message(kind, current, chosen)
      price = ActiveSupport::NumberHelper.number_to_currency(chosen[:price], unit: "R$", separator: ",", delimiter: ".")
      text = case kind
      when "aderir" then "Anúncio entrou em #{name_of(chosen)} a #{price}."
      when "ajustar_preco" then "Preço em #{name_of(chosen)} ajustado para #{price}."
      else "Anúncio trocou #{name_of(current)} por #{name_of(chosen)} a #{price}."
      end
      @forced_reason ? "#{text} Aplicado mesmo assim (#{@forced_reason}); fica registrado no Histórico." : text
    end

    NO_WRITE_PERMISSION = "o aplicativo do Lunna no Mercado Livre só tem permissão de leitura de promoções (ofertas). "                           "É preciso liberar leitura e escrita de Ofertas e Promoções no DevCenter e autorizar a conta de novo"

    # Só a mensagem do ML, sem a URL interna; 403 do PolicyAgent = falta de permissão de escrita no app.
    def ml_message(error)
      return NO_WRITE_PERMISSION if error.status == 403 && error.message.include?("PA_UNAUTHORIZED")

      error.message.split(" — ", 2).last.to_s.truncate(200)
    end
  end
end
