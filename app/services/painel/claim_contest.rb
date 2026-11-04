# Assistente de contestação (seção Reclamações; pedido do usuário em 04/11/2026): para cada reclamação que afeta a
# reputação e ainda está no prazo de contestação do ML (60 dias, contados da abertura), classifica o caso, reúne as
# provas que o Lunna tem e redige um texto para o vendedor revisar e enviar no Mercado Livre. Não envia nada: a
# contestação é feita pelo vendedor no ML (com a reclamação aberta, pode ir ao mediador pela visão "A atender").
#
# Grupos, do argumento mais forte ao mais fraco:
#   decisao_favor   — o ML decidiu a favor do vendedor (benefited respondent) e mesmo assim afetou;
#   nao_devolvido   — devolução expirada/cancelada: o comprador não devolveu o produto;
#   deposito        — o próprio ML registrou "decisão do depósito" (warehouse_decision);
#   full            — venda Full: separação, embalagem de envio e transporte são do ML;
#   anuncio         — "diferente do anúncio"/cor/modelo: comparar com o anúncio e com o que foi enviado;
#   envio           — envio pela agência/coleta: dano no transporte do Mercado Envios.
module Painel
  class ClaimContest
    WINDOW = 60.days
    GROUPS = {
      "decisao_favor" => [ "Decisão a seu favor", "alta" ], "nao_devolvido" => [ "Produto não devolvido", "alta" ],
      "deposito" => [ "Decisão do depósito do ML", "alta" ], "full" => [ "Venda Full (logística do ML)", "média" ],
      "anuncio" => [ "Produto x anúncio", "média" ], "envio" => [ "Envio pelo Mercado Envios", "baixa" ]
    }.freeze
    LISTING_REASONS = %w[different_than_published different_color_or_size sup_different_color_or_size different_item_other
                         different_item missing_accessories].freeze
    LOGISTICS = { "fulfillment" => "Full", "xd_drop_off" => "agência", "cross_docking" => "coleta", "self_service" => "Flex",
                  "drop_off" => "agência" }.freeze
    STATUSES = %w[pendente contestada aceita negada].freeze
    # O texto do motivo no ML às vezes é o título do grupo ("Chegou bem"); o código diz o problema de fato.
    REASON_LABELS = {
      "broken_item" => "produto chegou quebrado ou danificado", "not_working_item" => "produto não funciona",
      "missing_accessories" => "faltaram peças ou acessórios", "different_than_published" => "produto diferente do anúncio",
      "different_color_or_size" => "cor, tamanho ou modelo diferente", "sup_different_color_or_size" => "cor, tamanho ou modelo diferente",
      "different_item_other" => "recebeu outro produto", "different_item" => "recebeu outro produto",
      "undelivered_repentant_buyer" => "comprador desistiu da compra"
    }.freeze

    def self.list(account) = new(account).list

    def initialize(account)
      @account = account
      @zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
    end

    def list
      claims = @account.ml_claims.where(affects_reputation: true).where.not(details_synced_at: nil)
        .where("date_created > ?", WINDOW.ago).order(:date_created).to_a
      contests = @account.ml_claim_contests.where(claim_id: claims.map(&:claim_id)).index_by(&:claim_id)
      orders = load_orders(claims)
      items = MlOrderItem.where(order_id: orders.values.compact.map(&:order_id)).group_by(&:order_id)
      rows = claims.map { |c| build(c, orders[c.claim_id], items, contests[c.claim_id]) }
      { claims: rows.sort_by { |r| r[:deadline] },
        summary: { total: rows.size, by_group: rows.group_by { |r| r[:group] }.transform_values(&:size),
                   due_7d: rows.count { |r| r[:deadline] < 7.days.from_now },
                   by_status: rows.group_by { |r| r[:contest][:status] }.transform_values(&:size) } }
    end

    private

    def load_orders(claims)
      by_id = @account.ml_orders.where(order_id: claims.filter_map(&:order_id)).index_by(&:order_id)
      by_ship = @account.ml_orders.where(shipping_id: claims.select { |c| c.resource == "shipment" }.map(&:resource_id)).index_by(&:shipping_id)
      claims.to_h { |c| [ c.claim_id, (c.order_id && by_id[c.order_id]) || (c.resource == "shipment" && by_ship[c.resource_id]) || nil ] }
    end

    def build(c, order, items, contest)
      line = order && items[order.order_id]&.first
      ship = order&.shipment || {}
      logistic = ship["logistic_type"]
      group = group_for(c, logistic)
      label, strength = GROUPS.fetch(group)
      facts = facts_for(c, order, line, ship, logistic)
      {
        claim_id: c.claim_id, status: c.status, opened_at: c.date_created, deadline: c.date_created + WINDOW,
        days_left: ((c.date_created + WINDOW - Time.current) / 1.day).floor,
        group: group, group_label: label, strength: strength,
        reason: reason_text(c), reason_code: c.reason&.dig("name"),
        order_id: order&.order_id, sku: line&.sku, title: line&.title, logistic: LOGISTICS[logistic] || logistic,
        open_with_mediator: c.status == "opened" && ClaimsQuery.reply_targets(c).include?("mediator"),
        evidence: facts[:evidence], draft: draft(group, c, facts),
        contest: contest ? { status: contest.status, text: contest.text, contested_at: contest.contested_at, user: contest.user&.name }
                         : { status: "pendente", text: nil, contested_at: nil, user: nil },
        link: order ? "https://www.mercadolivre.com.br/vendas/#{order.order_id}/detalhe" : nil
      }
    end

    def group_for(c, logistic)
      res = c.resolution || {}
      return "decisao_favor" if Array(res["benefited"]).include?("respondent")
      return "nao_devolvido" if %w[expired cancelled].include?(c.devolution&.dig("status"))
      return "deposito" if res["reason"] == "warehouse_decision"
      return "full" if logistic == "fulfillment"
      return "anuncio" if LISTING_REASONS.include?(c.reason&.dig("name"))

      "envio"
    end

    # Provas em frases curtas, com datas, a partir do que o ML informou e do que o Lunna guarda da venda.
    def facts_for(c, order, line, ship, logistic)
      res = c.resolution || {}
      dev = c.devolution || {}
      ev = []
      ev << "Reclamação #{c.claim_id} aberta em #{d(c.date_created)}; motivo: #{reason_text(c)}."
      if order
        ev << "Venda ##{order.order_id} de #{d(order.date_created)}: #{line&.title} (SKU #{line&.sku || '—'}), envio #{LOGISTICS[logistic] || logistic || '—'}."
        hist = ship["status_history"] || {}
        ev << "Postado/expedido em #{d(hist['date_shipped'])} e entregue em #{d(hist['date_delivered'])}." if hist["date_delivered"]
      end
      opened_dispute = Array(c.status_history).find { |h| h["stage"] == "dispute" && h["status"] == "opened" }
      ev << "Mediação aberta por #{who(opened_dispute['change_by'])} em #{d(opened_dispute['date'])}." if opened_dispute
      if res.present?
        ev << "Resolução do ML: #{res_label(res['reason'])}, a favor de #{Array(res['benefited']).map { |b| who(b) }.join(', ')}, " \
              "encerrada por #{who(res['closed_by'])} em #{d(res['date_created'])}#{res['applied_coverage'] ? '; com cobertura do Mercado Livre' : ''}."
      end
      if dev.present?
        track = Array(dev["shipments"]).find { |s| s["type"] == "return" } || Array(dev["shipments"]).first || {}
        ev << "Devolução: #{dev_label(dev['status'])}#{dev['date_closed'] ? " (#{d(dev['date_closed'])})" : ''}#{track['tracking_number'] ? ", rastreio #{track['tracking_number']}" : ''}."
      end
      stated = buyer_statement(c)
      ev << "Segundo o resumo do mediador: \"#{stated}\"" if stated
      seller_msgs = Array(c.messages).count { |m| m["sender_role"] == "respondent" }
      ev << "Você enviou #{seller_msgs} mensagem(ns) durante a reclamação." if seller_msgs.positive?
      { evidence: ev, stated: stated, order: order, line: line, logistic: logistic, res: res, dev: dev }
    end

    # Frase do assistente do ML que resume o relato do comprador ("O comprador informou que ...").
    def buyer_statement(c)
      Array(c.messages).each do |m|
        text = ActionView::Base.full_sanitizer.sanitize(m["message"].to_s).gsub("**", "")
        found = text[/(?:O|A) compradora? informou[^.]*\.(?:[^.]*embalagem[^.]*\.)?/]
        return found.squish.truncate(300) if found
      end
      nil
    end

    def draft(group, c, f)
      sale = f[:order] ? "à venda ##{f[:order].order_id} (#{f[:line]&.title})" : "à reclamação #{c.claim_id}"
      intro = "Olá. Solicito a revisão da reclamação #{c.claim_id}, referente #{sale}, para que ela não seja considerada na reputação da minha conta."
      body =
        case group
        when "decisao_favor"
          "A reclamação foi encerrada com decisão a meu favor (#{res_label(f[:res]['reason'])}), conforme registrado pelo próprio Mercado Livre em #{d(f[:res]['date_created'])}. Como o caso foi resolvido a favor do vendedor, entendo que ele não deveria impactar a minha reputação."
        when "nao_devolvido"
          "Foi gerada a devolução do produto, mas o comprador não a realizou no prazo (devolução #{dev_label(f[:dev]['status']).downcase}). O produto não retornou e não houve comprovação do problema relatado, por isso peço que a reclamação não afete a minha reputação."
        when "deposito"
          "O próprio Mercado Livre registrou a resolução como decisão do depósito. Trata-se de venda pelo Full: o produto foi armazenado, separado, embalado para envio e transportado pela logística do Mercado Livre, sem participação minha após a entrada no depósito."
        when "full"
          full_body(c)
        when "anuncio"
          "O produto enviado corresponde ao anúncio (título, ficha técnica, fotos e variação escolhida pelo comprador). Peço que a diferença relatada seja verificada com base no anúncio e no produto devolvido, já que não houve divergência no que foi anunciado."
        else
          "O envio foi feito pelo Mercado Envios, com o produto em perfeitas condições na postagem. O problema relatado decorre do transporte, que é de responsabilidade da logística do Mercado Livre."
        end
      stated = f[:stated] && f[:stated].match?(/embalagem n[ãa]o estava danificada/i) && group.in?(%w[full deposito]) ?
        " Além disso, o próprio relato registrado pelo mediador informa que a embalagem não estava danificada, o que afasta falha de envio da minha parte." : ""
      "#{intro}\n\n#{body}#{stated}\n\nAgradeço a análise."
    end

    # Full: o argumento depende do problema relatado (dano = transporte; item diferente/faltando = separação no depósito;
    # defeito = pedir a análise do produto devolvido).
    def full_body(c)
      base = "Esta venda foi pelo Full: armazenamento, separação, embalagem de envio e transporte foram feitos pela logística do Mercado Livre, sem participação minha na expedição."
      case c.reason&.dig("name").to_s
      when "broken_item"
        "#{base} O dano relatado (#{reason_text(c)}) ocorreu com o produto sob a guarda e o transporte do Mercado Livre."
      when *LISTING_REASONS
        "#{base} A separação do item enviado ao comprador é feita pelo depósito do Mercado Livre a partir do estoque recebido e conferido na entrada do Full; a divergência relatada (#{reason_text(c)}) não decorre do anúncio, que está correto."
      else
        "#{base} Peço que o problema relatado (#{reason_text(c)}) seja avaliado a partir do produto devolvido antes de impactar a minha reputação."
      end
    end

    def reason_text(c)
      REASON_LABELS[c.reason&.dig("name").to_s] || c.reason_detail || c.reason_id || "—"
    end

    def d(value)
      return "—" if value.blank?

      (value.is_a?(String) ? Time.zone.parse(value) : value).in_time_zone(@zone).strftime("%d/%m/%Y")
    rescue ArgumentError
      value.to_s
    end

    def who(role) = { "complainant" => "comprador", "respondent" => "vendedor", "mediator" => "Mercado Livre", "seller" => "vendedor", "buyer" => "comprador" }[role.to_s] || role.to_s

    def res_label(reason)
      { "item_returned" => "produto devolvido", "coverage_decision" => "decisão com cobertura do ML", "warehouse_decision" => "decisão do depósito",
        "no_bpp" => "sem proteção de compra para o comprador", "return_expired" => "devolução expirada", "payment_refunded" => "pagamento reembolsado",
        "timeout" => "prazo esgotado", "product_delivered" => "produto entregue" }[reason.to_s] || reason.to_s
    end

    def dev_label(status)
      { "delivered" => "Entregue ao vendedor", "shipped" => "A caminho", "expired" => "Expirada", "cancelled" => "Cancelada",
        "label_generated" => "Etiqueta gerada" }[status.to_s] || status.to_s
    end
  end
end
