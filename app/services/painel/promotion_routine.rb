# Rotina das 03:00 da seção Promoções. Relê a Central de Promoções, calcula a melhor oferta de cada anúncio ativo com
# todas as regras (margem/valor, preço cheio, limite de aumento por faixa, casa de cem) e, conforme o modo da empresa:
#   - simulation: só registra o que faria (nada muda no Mercado Livre);
#   - apply: aplica no ML pela mesma regra da tela (Painel::PromotionActions), um anúncio de cada vez.
# Cada anúncio vira uma linha em ml_promotion_actions ligada à execução (run_id), com o antes e o depois.
#
# O que a rotina faz em cada situação:
#   - trocar, sem promoção (inclui promoção que acabou ou caiu), acima da máxima, abaixo da mínima com oferta que
#     serve: aplica a melhor oferta;
#   - para revisar: não mexe e registra a regra que barrou;
#   - na melhor, sem custo: não mexe;
#   - anúncio com regra própria em texto, ou com a automação desligada: não mexe e registra o motivo (o texto é para
#     quem opera ler; a rotina não interpreta regras escritas).
module Painel
  class PromotionRoutine
    ACT_ON = %w[trocar sem_promocao acima_maxima abaixo_minima].freeze

    def self.call(account, mode:, trigger: "agendada", user: nil)
      new(account, mode, trigger, user).call
    end

    def initialize(account, mode, trigger, user)
      @account = account
      @mode = mode
      @trigger = trigger
      @user = user
    end

    def call
      run = @account.ml_promotion_runs.create!(mode: @mode, trigger: @trigger, user: @user, started_at: Time.current)
      Ml::OAuth.refresh!(@account)
      Ml::Sync::Promotions.call(Ml::Client.new(access_token: @account.access_token), @account)

      totals = Hash.new(0)
      PromotionsQuery.evaluate_all(@account).each do |ev|
        outcome = handle(run, ev)
        totals[outcome] += 1
      end
      run.update!(status: "done", finished_at: Time.current, totals: totals.merge("anuncios" => totals.values.sum))
      run
    rescue Ml::OAuth::Error => e
      run&.update!(status: "failed", finished_at: Time.current, error: "Conta do Mercado Livre precisa ser autorizada de novo: #{e.message}".truncate(500))
      run
    rescue StandardError => e
      run&.update!(status: "failed", finished_at: Time.current, error: e.message.truncate(500))
      raise
    end

    private

    # => chave do total: aplicado | simulado | erro | revisar | regra_propria | automacao_desligada | sem_mudanca
    def handle(run, ev)
      row = ev[:row]
      status = row[:status][:key]
      setting = ev[:setting]

      if setting && !setting.automation_enabled
        # "não automatizar": não mexe, mas registra a melhor oferta como sugestão
        return skip(run, ev, "automacao_desligada", "marcado para não automatizar promoções (só muda pela tela)", to: ev[:best].present? && !ev[:best][:as_is])
      end
      if status == "para_revisar"
        return skip(run, ev, "revisar", row.dig(:review, :label) || "nenhuma oferta cabe nas regras", kind: "revisar")
      end
      return "sem_mudanca" unless ACT_ON.include?(status) && ev[:best] && !ev[:best][:as_is]
      return skip(run, ev, "regra_propria", "regra própria do anúncio: #{setting.rules_note.truncate(120)}") if setting&.rules_note.present?

      @mode == "apply" ? apply(run, ev) : simulate(run, ev)
    end

    def simulate(run, ev)
      current, best = ev[:current], ev[:best]
      kind = if current.nil? then "aderir"
      elsif current[:offer].promotion_id == best[:offer].promotion_id && current[:offer].promotion_type == best[:offer].promotion_type then "ajustar_preco"
      else "trocar"
      end
      record(run, ev, kind, ok: true)
      "simulado"
    end

    def apply(run, ev)
      result = PromotionActions.apply(@account, ev[:item].item_id, source: "rotina", run: run)
      result.ok ? "aplicado" : "erro"
    rescue Ml::Client::Error, ActiveRecord::RecordNotFound => e
      record(run, ev, "trocar", ok: false, error: e.message)
      "erro"
    end

    def skip(run, ev, key, reason, kind: "pular", to: false)
      record(run, ev, kind, ok: true, error: reason, to: to)
      key
    end

    def record(run, ev, kind, ok:, error: nil, to: true)
      from = ev[:current]
      best = to ? ev[:best] : ev[:row].dig(:review, :blocked_best)
      @account.ml_promotion_actions.create!(
        run: run, item_id: ev[:item].item_id, kind: kind, source: @mode == "apply" ? "rotina" : "simulacao", user: @user,
        ok: ok, error: error&.truncate(500),
        from_promotion_id: from&.dig(:offer)&.promotion_id, from_type: from&.dig(:offer)&.promotion_type,
        from_name: from && (from[:offer].name.presence || from[:label]), from_price: from&.dig(:price),
        from_margin_pct: from&.dig(:margin_pct), from_profit: from&.dig(:profit),
        to_promotion_id: offer_of(best)&.promotion_id, to_type: offer_of(best)&.promotion_type,
        to_name: best && (offer_of(best)&.name.presence || best[:label] || best[:name]), to_price: best&.dig(:price),
        to_margin_pct: best&.dig(:margin_pct), to_profit: best&.dig(:profit),
        gain: to && from && best ? (best[:profit] - from[:profit]).round(2) : nil
      )
    end

    # A melhor oferta vem como avaliação (com :offer) e a barrada da revisão vem já resumida (sem :offer).
    def offer_of(entry)
      return nil if entry.nil?

      entry[:offer] || Struct.new(:promotion_id, :promotion_type, :name).new(entry[:promotion_id], entry[:type], entry[:name])
    end
  end
end
