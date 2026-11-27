# Referência fixa da redução de margem em Promoções (27/11/2026, pedido do usuário: "travar a escada").
#
# Com "Permitir reduzir o preço mesmo com redução da margem" ligado, a tolerância (ex.: 0,5 p.p.) era medida contra a
# promoção do dia: a cada rodada a automação podia descer mais 0,5 p.p. Agora ela é medida contra uma referência por
# anúncio, e as reduções somadas não passam da tolerância abaixo dela.
#
# A referência é:
#   - a margem logo depois da última decisão manual sobre o anúncio (aplicar, aplicar mesmo assim, cabível, outro valor,
#     lote pela tela, sair, "ciente") — source "manual";
#   - sem decisão manual, a margem de antes da primeira redução feita pela automação — source "automacao";
#   - na implantação, a margem de hoje de cada anúncio em promoção — source "inicial" (nada é revertido no ML).
# Ela é renovada (passa a valer a margem de hoje) quando o usuário decide manualmente, quando mudam as configurações de
# margem/tolerância (gerais ou do anúncio) ou quando o custo do produto muda: a `key` guarda essas configurações e, se
# não bater mais, a referência gravada é ignorada. Cada troca fica em `log` (auditoria).
# A regra de "acima da máxima" (descer até o alvo) e o piso da margem mínima não mudam: sem trava, a referência não entra.
module Painel
  module PromotionDropRef
    LOG_LIMIT = 30

    module_function

    # Configurações que, se mudarem, renovam a referência (margem/tolerância gerais e do anúncio, base e custo).
    def key_for(company, setting, cost)
      parts = [
        company.promo_margin_basis, company.promo_margin_drop_tolerance&.to_f, company.min_margin_pct&.to_f, company.max_margin_pct&.to_f,
        setting&.limit_mode, setting&.min_margin_pct&.to_f, setting&.max_margin_pct&.to_f, setting&.min_price&.to_f, setting&.max_price&.to_f,
        cost&.to_f&.round(2)
      ]
      Digest::SHA1.hexdigest(parts.map(&:to_s).join("|"))[0, 16]
    end

    # A margem de referência que vale (nil = não há, ou as configurações/custo mudaram: vale a margem de hoje).
    def effective(ref, key)
      ref && ref.key == key ? ref.margin_pct.to_f : nil
    end

    # Grava (ou renova) a referência de um anúncio e registra no log.
    def record!(account, item_id, margin_pct, source:, key:, user: nil, note: nil)
      return nil if margin_pct.nil?

      ref = account.ml_promotion_drop_refs.find_or_initialize_by(item_id: item_id)
      entry = { "at" => Time.current.iso8601, "margin_pct" => margin_pct.to_f.round(2), "source" => source, "user" => user&.name, "note" => note,
                "previous" => ref.persisted? ? ref.margin_pct.to_f : nil }.compact
      ref.assign_attributes(margin_pct: margin_pct.to_f.round(2), set_at: Time.current, source: source, key: key, user: user,
                            log: ((ref.log || []) + [ entry ]).last(LOG_LIMIT))
      ref.save!
      ref
    end

    # Renova (passa a valer a margem de hoje) sem apagar o histórico: a chave deixa de bater e o log registra o motivo.
    def renew!(account, item_id, source:, user: nil, note: nil)
      ref = account.ml_promotion_drop_refs.find_by(item_id: item_id)
      return nil unless ref

      entry = { "at" => Time.current.iso8601, "source" => source, "user" => user&.name, "note" => note || "renovada: vale a margem de hoje",
                "previous" => ref.margin_pct.to_f }.compact
      ref.update!(key: "renovada", log: ((ref.log || []) + [ entry ]).last(LOG_LIMIT))
      ref
    end

    # Implantação (27/11/2026): cada anúncio em promoção dentro dos limites começa com a margem de hoje como referência.
    # Nada muda no Mercado Livre. => quantos anúncios ganharam referência.
    def initialize_all!(account)
      return 0 unless account.company.promo_allow_margin_drop

      PromotionsQuery.evaluate_all(account).count do |ev|
        next false if ev[:error] || ev[:evaluator].nil?

        d = ev[:evaluator].drop_info
        next false if d.nil? || d[:stored]

        record!(account, ev[:item].item_id, d[:today_pct], source: "inicial", key: ev[:drop_key], note: "implantação: margem de hoje")
        true
      end
    end

    # Resumo para a tela (painel do anúncio): referência, de quando, de onde e quanto da tolerância já foi usado.
    def info(ref, key, evaluator)
      d = evaluator&.drop_info
      return nil unless d

      stored = effective(ref, key)
      { ref_pct: d[:ref_pct], today_pct: d[:today_pct], tolerance_pp: d[:tolerance_pp], used_pp: d[:used_pp], floor_pct: d[:floor_pct],
        set_at: stored ? ref.set_at : nil, source: stored ? ref.source : nil,
        renewed: ref.present? && stored.nil? }
    end
  end
end
