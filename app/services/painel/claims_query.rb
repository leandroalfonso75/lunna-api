# Seção Reclamações (GET /api/claims e /api/claims/:id): lista de todas as reclamações importadas do Mercado Livre
# (Ml::Sync::ClaimsCenter) com a venda ligada (pelo pedido ou pelo envio) e, no detalhe, tudo o que a API informou.
# Por enquanto só busca e paginação; filtros e regras vêm depois (pedido do usuário em 03/11/2026).
module Painel
  class ClaimsQuery
    PER_PAGES = [ 25, 50, 100 ].freeze
    TYPES = { "mediations" => "Reclamação", "cancel_purchase" => "Cancelamento", "returns" => "Devolução" }.freeze
    STAGES = { "claim" => "Reclamação", "dispute" => "Mediação", "recontact" => "Recontato", "none" => "—" }.freeze
    STATUSES = { "opened" => [ "Aberta", "warn" ], "closed" => [ "Encerrada", "neutral" ] }.freeze
    ROLES = { "seller" => "Você", "respondent" => "Você", "buyer" => "Comprador", "complainant" => "Comprador",
              "mediator" => "Mercado Livre", "internal" => "Mercado Livre" }.freeze
    # Devolução (status da devolução no ML, /v2/claims/{id}/returns) → coluna "Devolução efetivada".
    RETURN_STATES = {
      "delivered" => [ "devolvida", "Devolvida", "ok" ], "shipped" => [ "a_caminho", "A caminho", "warn" ],
      "label_generated" => [ "aguardando", "Aguardando", "neutral" ], "pending" => [ "aguardando", "Aguardando", "neutral" ],
      "ready_to_ship" => [ "aguardando", "Aguardando", "neutral" ],
      "expired" => [ "nao_devolvida", "Não devolvida", "bad" ], "cancelled" => [ "nao_devolvida", "Não devolvida", "bad" ],
      "failed" => [ "nao_devolvida", "Não devolvida", "bad" ], "not_delivered" => [ "nao_devolvida", "Não devolvida", "bad" ]
    }.freeze
    # Ações do ML que habilitam a devolução mesmo antes de a devolução existir.
    RETURN_ACTIONS = %w[allow_return generate_return generate_return_async].freeze
    EXPECTED = { "return_product" => "Devolver o produto", "refund" => "Reembolso", "change_product" => "Troca do produto",
                 "partial_refund" => "Reembolso parcial", "product" => "Receber o produto", "allow_return" => "Permitir devolução" }.freeze

    # Ações que o ML libera ao vendedor numa reclamação (players[respondent].available_actions).
    ACTIONS = {
      "send_message_to_complainant" => "Mandar mensagem ao comprador", "send_message_to_mediator" => "Mandar mensagem ao mediador",
      "refund" => "Reembolsar o comprador", "open_dispute" => "Pedir mediação do Mercado Livre", "allow_return" => "Permitir devolução",
      "send_potential_shipping" => "Informar envio", "add_shipping_evidence" => "Enviar comprovante de envio",
      "send_attachments" => "Enviar anexos", "partial_refund" => "Reembolso parcial"
    }.freeze
    SELLER_ROLES = %w[seller respondent].freeze

    # Para quem o vendedor pode mandar mensagem agora (pelas ações liberadas pelo ML). Sem a ação, o ML recusa
    # ("send message is not allowed", conferido em 10/11/2026 na #2000015809880991).
    def self.reply_targets(claim)
      return [] unless claim.status == "opened"

      actions = seller_actions(claim).map { |a| a["action"] }
      ClaimReply::RECEIVER_ACTIONS.select { |_, action| actions.include?(action) }.keys
    end

    # Aguarda o vendedor, mas o ML não libera nenhuma ação pela integração (fluxo guiado do "Atender reclamação", com o
    # assistente do ML): a resposta só pode ser dada no painel do Mercado Livre.
    def self.ml_only?(claim) = claim.status == "opened" && seller_actions(claim).empty? && SELLER_ROLES.include?(claim.action_responsible.to_s)

    def self.seller_actions(claim)
      Array(Array(claim.players).find { |p| p["role"] == "respondent" }&.dig("available_actions"))
    end

    # A atender: aberta e o ML aguarda o vendedor — vale o "responsável pela próxima ação" do detalhe do ML (o que o painel
    # do ML usa para o botão "Atender reclamação") ou uma ação obrigatória. Quando o comprador aceita a solução, o ML
    # passa o responsável para o comprador e ela sai de A atender; as abertas são relidas a cada 15 minutos.
    # 10/11/2026: até aqui também exigia ação liberada ao vendedor; reclamação recém-aberta (sem ações ainda na lista do
    # ML) ficava de fora (#2000015809880991).
    def self.to_attend?(claim)
      claim.status == "opened" &&
        (SELLER_ROLES.include?(claim.action_responsible.to_s) || seller_actions(claim).any? { |a| a["mandatory"] })
    end

    def self.list(account, params) = new(account, params).list
    def self.detail(account, claim_id) = new(account, {}).detail(claim_id)

    def initialize(account, params)
      @account = account
      @params = params
    end

    # Período pela data de abertura (como em Vendas): presets, mês (YYYY-MM) ou datas; "all" = todas (padrão).
    PRESETS = { "today" => 1, "yesterday" => 1, "7d" => 7, "30d" => 30, "60d" => 60, "90d" => 90, "365d" => 365 }.freeze
    # Ordenação por coluna (pedido do usuário em 03/11/2026). Colunas calculadas (devolução, reembolso, frete) são
    # ordenadas depois de montar as linhas; vazio ("carregando…") vai sempre para o fim.
    SORTS = {
      "date" => ->(r) { r[:date_created].to_i }, "type" => ->(r) { r[:type_label] }, "reason" => ->(r) { r[:reason] },
      "status" => ->(r) { r[:status_label] }, "return_enabled" => ->(r) { { true => 1, false => 0 }[r.dig(:devolution_status, :enabled)] },
      "return_state" => ->(r) { r.dig(:devolution_status, :label) }, "refund" => ->(r) { r.dig(:refund, :label) },
      "freight" => ->(r) { r.dig(:freight, :amount) || ({ "nao" => 0 }[r.dig(:freight, :key)]) },
      "reputation" => ->(r) { { true => 1, false => 0 }[r[:affects_reputation]] }
    }.freeze
    ZONE = ActiveSupport::TimeZone["America/Sao_Paulo"]

    def list
      from, to = window
      scope = search(@account.ml_claims)
      scope = scope.where(date_created: from..to) if from
      view = @params[:view].to_s
      scope = scope.where(status: "opened") if %w[atender abertas].include?(view)
      # na visão "A atender"/"Abertas" (poucas) vem tudo, inclusive o detalhe e a última mensagem
      columns = view.present? ? MlClaim.column_names - %w[raw changes_log reason] : MlClaim.column_names - %w[raw detail messages changes_log evidences reason status_history]
      claims = scope.select(columns).to_a
      claims = claims.select { |c| self.class.to_attend?(c) } if view == "atender"
      orders = orders_for(claims)
      rows = claims.map { |c| row(c, orders[c.claim_id]) }
      rows = view.present? && @params[:sort].blank? ? rows.sort_by { |r| [ r[:to_attend] ? 0 : 1, r[:deadline] || Time.utc(3000) ] } : sort(rows)
      per = PER_PAGES.include?(@params[:per_page].to_i) ? @params[:per_page].to_i : 50
      page = [ @params[:page].to_i, 1 ].max
      {
        claims: rows.slice((page - 1) * per, per) || [],
        total: rows.size, page: page, per_page: per, sort: sort_key, dir: sort_dir,
        period: { preset: preset_key, month: month_key, from: from&.iso8601, to: to&.iso8601 },
        months: available_months,
        view: view.presence,
        attention: attention_info,
        import: import_info
      }
    end

    def detail(claim_id)
      claim = @account.ml_claims.find_by!(claim_id: claim_id)
      order = orders_for([ claim ])[claim.claim_id]
      row(claim, order).merge(
        detail: claim.detail, players: claim.players.map { |p| p.merge("role_label" => ROLES[p["role"]] || p["role"]) },
        messages: claim.messages.map { |m| message(m) }.sort_by { |m| m[:date].to_s },
        status_history: claim.status_history, actions_history: claim.actions_history,
        expected_resolutions: claim.expected_resolutions.map { |e| e.merge("label" => EXPECTED[e["expected_resolution"]] || e["expected_resolution"]) },
        evidences: claim.evidences, changes: claim.changes_log, reputation: claim.reputation, devolution: claim.devolution,
        reason_info: claim.reason, resolution_raw: claim.resolution, related_entities: claim.related_entities,
        detail_errors: claim.detail_errors, raw: claim.raw
      )
    end

    private

    def sort_key = SORTS.key?(@params[:sort].to_s) ? @params[:sort].to_s : "date"
    def sort_dir = @params[:dir].to_s == "asc" ? "asc" : "desc"

    def sort(rows)
      key = SORTS.fetch(sort_key)
      filled, empty = rows.partition { |r| !key.(r).nil? }
      sorted = filled.sort_by { |r| [ key.(r), r[:date_created].to_i ] }
      sorted = sorted.reverse if sort_dir == "desc"
      sorted + empty.sort_by { |r| -r[:date_created].to_i }
    end

    def preset_key
      return "custom" if custom_dates?
      return "month" if month_key

      PRESETS.key?(@params[:period].to_s) ? @params[:period].to_s : "all"
    end

    def custom_dates? = @params[:from].present? && @params[:to].present?

    def month_key
      key = @params[:month].to_s
      key.match?(/\A\d{4}-\d{2}\z/) && available_months.any? { |m| m[:value] == key } ? key : nil
    end

    # Meses com reclamação, do mais novo para o mais antigo (o atual sempre primeiro).
    def available_months
      @available_months ||= begin
        today = ZONE.today
        keys = @account.ml_claims.where.not(date_created: nil)
          .pluck(Arel.sql("DISTINCT to_char(date_created AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM')"))
        keys = (keys + [ today.strftime("%Y-%m") ]).uniq.sort.reverse
        keys.map { |k| { value: k, label: "#{k[5, 2]}/#{k[0, 4]}", current: k == today.strftime("%Y-%m") } }
      end
    end

    # => [início, fim] em horário de Brasília, ou [nil, nil] para todas.
    def window
      today = ZONE.today
      if custom_dates?
        first = Date.parse(@params[:from].to_s) rescue nil
        last = Date.parse(@params[:to].to_s) rescue nil
        return [ first.in_time_zone(ZONE).beginning_of_day, last.in_time_zone(ZONE).end_of_day ] if first && last
      end
      if (key = month_key)
        start = Date.strptime(key, "%Y-%m")
        return [ start.in_time_zone(ZONE).beginning_of_day, [ start.end_of_month, today ].min.in_time_zone(ZONE).end_of_day ]
      end

      case preset_key
      when "today" then [ today.in_time_zone(ZONE).beginning_of_day, ZONE.now.end_of_day ]
      when "yesterday" then [ (today - 1).in_time_zone(ZONE).beginning_of_day, (today - 1).in_time_zone(ZONE).end_of_day ]
      when "all" then [ nil, nil ]
      else [ (today - (PRESETS.fetch(preset_key) - 1)).in_time_zone(ZONE).beginning_of_day, ZONE.now.end_of_day ]
      end
    end

    def search(scope)
      q = @params[:q].to_s.strip
      return scope if q.blank?

      if q.match?(/\A\d+\z/)
        n = q.to_i
        shipping_ids = @account.ml_orders.where(order_id: n).pluck(:shipping_id).compact
        scope.where(claim_id: n).or(scope.where(order_id: n)).or(scope.where(resource_id: [ n ] + shipping_ids))
      else
        like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
        order_ids = @account.ml_orders.where("buyer_nickname ILIKE :l OR buyer_name ILIKE :l", l: like).pluck(:order_id, :shipping_id)
        by_item = MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
          .where(o: { ml_account_id: @account.id }).where("ml_order_items.title ILIKE :l OR ml_order_items.sku ILIKE :l", l: like)
          .pluck("o.order_id", "o.shipping_id")
        ids = (order_ids + by_item).uniq
        scope.where("reason_detail ILIKE :l OR detail_title ILIKE :l", l: like)
          .or(scope.where(order_id: ids.map(&:first))).or(scope.where(resource_id: ids.map(&:last).compact))
      end
    end

    # Venda ligada a cada reclamação: pelo pedido (resource order) ou pelo envio (resource shipment).
    def orders_for(claims)
      by_order = claims.filter_map(&:order_id)
      by_ship = claims.select { |c| c.resource == "shipment" }.map(&:resource_id)
      orders = @account.ml_orders.where(order_id: by_order).or(@account.ml_orders.where(shipping_id: by_ship))
        .select(:order_id, :shipping_id, :buyer_nickname, :buyer_name, :total_amount, :paid_amount, :date_created, :status,
                Arel.sql("payload->'payments' AS payments"), Arel.sql("shipment->>'logistic_type' AS logistic_type")).to_a
      items = MlOrderItem.where(order_id: orders.map(&:order_id)).group_by(&:order_id)
      thumbs = @account.ml_items.where(item_id: items.values.flatten.map(&:item_id).uniq).pluck(:item_id, :thumbnail).to_h
      by_id = orders.index_by(&:order_id)
      by_shipping = orders.select(&:shipping_id).index_by(&:shipping_id)
      claims.to_h do |c|
        o = (c.order_id && by_id[c.order_id]) || (c.resource == "shipment" && by_shipping[c.resource_id]) || nil
        line = o && items[o.order_id]&.first
        [ c.claim_id, o && { order_id: o.order_id, buyer_nickname: o.buyer_nickname, buyer_name: o.buyer_name,
                             total: o.total_amount&.to_f, date_created: o.date_created, status: o.status,
                             # tipo de envio da venda (Full, Agência, Flex, Coleta), pedido do usuário em 13/11/2026
                             logistic_type: o.attributes["logistic_type"], logistic: logistic_label(o.attributes["logistic_type"]),
                             payments: Array(o.attributes["payments"]).map { |p| p.slice("status", "transaction_amount", "total_paid_amount", "transaction_amount_refunded", "shipping_cost") },
                             item: line && { item_id: line.item_id, title: line.title, sku: line.sku, quantity: line.quantity,
                                             thumbnail: thumbs[line.item_id] } } ]
      end
    end

    LOGISTIC_LABELS = { "fulfillment" => "Full", "xd_drop_off" => "Agência", "drop_off" => "Agência", "self_service" => "Flex",
                        "cross_docking" => "Coleta" }.freeze

    def logistic_label(type) = type.present? ? LOGISTIC_LABELS.fetch(type, type) : nil

    def row(c, order)
      status, tone = STATUSES.fetch(c.status, [ c.status.to_s, "neutral" ])
      {
        claim_id: c.claim_id, type: c.claim_type, type_label: TYPES[c.claim_type] || c.claim_type,
        stage: c.stage, stage_label: STAGES[c.stage] || c.stage, status: c.status, status_label: status, tone: tone,
        reason_id: c.reason_id, reason: c.reason_detail, reason_name: c.reason_name,
        date_created: c.date_created, last_updated: c.last_updated,
        resource: c.resource, resource_id: c.resource_id,
        title: c.detail_title, action_responsible: c.action_responsible,
        action_responsible_label: c.action_responsible && (ROLES[c.action_responsible] || c.action_responsible), due_date: c.due_date,
        affects_reputation: c.affects_reputation, reputation_status: c.reputation_status, has_incentive: c.has_incentive,
        resolution: c.resolution && { reason: c.resolution["reason"], benefited: Array(c.resolution["benefited"]),
                                      closed_by: c.resolution["closed_by"], date: c.resolution["date_created"] },
        devolution_status: return_info(c),
        to_attend: self.class.to_attend?(c),
        deadline: c.due_date,
        seller_actions: c.status == "opened" ? self.class.seller_actions(c).map { |a| { action: a["action"], label: ACTIONS[a["action"]] || a["action"], due_date: a["due_date"], mandatory: a["mandatory"] } } : [],
        reply_targets: self.class.reply_targets(c), ml_only: self.class.ml_only?(c),
        resolve_actions: ClaimAction.available(c),
        buyer_wants: Array(c.expected_resolutions).select { |e| e["player_role"] == "complainant" }.map { |e| EXPECTED[e["expected_resolution"]] || e["expected_resolution"] }.uniq,
        what_to_do: c.has_attribute?(:detail) && c.detail.present? ? { title: c.detail["title"], description: c.detail["description"] } : (c.detail_title && { title: c.detail_title, description: c.detail_description }),
        last_message: c.has_attribute?(:messages) && c.messages.present? ? message(c.messages.max_by { |m| m["message_date"].presence || m["date_created"].to_s }) : nil,
        refund: refund_info(c, order),
        freight: freight_info(c),
        order: order, detailed: c.details_synced_at.present?,
        link: c.order_id || order ? "https://www.mercadolivre.com.br/vendas/#{order&.dig(:order_id) || c.order_id}/detalhe" : nil
      }
    end

    # "Devolução habilitada" (Sim/Não) e "Devolução efetivada" (Devolvida, Não devolvida, A caminho, Aguardando).
    # Aguardando = etiqueta gerada / ainda dentro do prazo de postagem; Não devolvida = prazo expirou ou devolução cancelada.
    def return_info(c)
      return { enabled: nil } unless c.details_synced_at

      d = c.devolution
      enabled = d.present? || Array(c.actions_history).any? { |a| RETURN_ACTIONS.include?(a["action_name"]) }
      return { enabled: false } unless enabled
      if d.blank?
        # autorizada, mas sem devolução gerada: aberta ainda pode ser postada; encerrada não foi devolvida
        return { enabled: true, key: "aguardando", label: "Aguardando", tone: "neutral", status: nil } if c.status == "opened"

        return { enabled: true, key: "nao_devolvida", label: "Não devolvida", tone: "bad", status: nil }
      end

      key, label, tone = RETURN_STATES.fetch(d["status"].to_s, [ d["status"].to_s, d["status"].to_s.tr("_", " ").capitalize, "neutral" ])
      shipment = Array(d["shipments"]).find { |s| s["type"] == "return" } || Array(d["shipments"]).first || {}
      { enabled: true, key: key, label: label, tone: tone, status: d["status"], shipment_status: shipment["status"],
        tracking: shipment["tracking_number"], refund_at: d["refund_at"], money: d["status_money"],
        date: d["date_closed"] || d["last_updated"] }
    end

    # Reembolso ao comprador: pelos pagamentos da venda (estornado x pago); sem a venda no Lunna (mais de 3 meses),
    # pelo que o ML registrou na reclamação (resolução esperada aceita, dinheiro da devolução estornado, resolução).
    def refund_info(c, order)
      payments = Array(order&.dig(:payments))
      if payments.any?
        paid = payments.sum { |p| p["total_paid_amount"].to_f.positive? ? p["total_paid_amount"].to_f : p["transaction_amount"].to_f }
        refunded = payments.sum { |p| p["transaction_amount_refunded"].to_f }
        return refund_hash("sem", c, source: "pagamento") if refunded <= 0.009
        kind = refunded >= payments.sum { |p| p["transaction_amount"].to_f } - 0.01 ? "integral" : "parcial"
        return refund_hash(kind, c, amount: refunded.round(2), paid: paid.round(2), source: "pagamento")
      end
      return { key: nil, label: nil } unless c.details_synced_at

      accepted = ->(type) { Array(c.expected_resolutions).any? { |e| e["expected_resolution"] == type && e["status"] == "accepted" } }
      return refund_hash("parcial", c, source: "reclamacao") if accepted.("partial_coverage") || accepted.("partial_refund")
      if accepted.("refund") || c.devolution&.dig("status_money") == "refunded" || c.resolution&.dig("reason") == "payment_refunded"
        return refund_hash("integral", c, source: "reclamacao")
      end

      refund_hash("sem", c, source: "reclamacao")
    end

    def refund_hash(kind, c, amount: nil, paid: nil, source: nil)
      label = { "integral" => "Reembolso integral", "parcial" => "Reembolso parcial" }[kind]
      label ||= c.status == "opened" ? "Sem reembolso (até agora)" : "Sem reembolso"
      { key: kind, label: label, amount: amount, paid: paid, source: source }
    end

    # Custo com frete na devolução: o que o envio de retorno custou ao vendedor (ou o valor que o ML informou na
    # mensagem, quando informou). Sem devolução, não houve frete de retorno.
    def freight_info(c)
      return { key: nil } unless c.details_synced_at
      return { key: "nao", label: "Não" } if c.devolution.blank?

      # devolução que não aconteceu (prazo expirou, cancelada): a etiqueta não foi usada, não há frete de retorno
      state = RETURN_STATES.dig(c.devolution["status"].to_s, 0)
      return { key: "nao", label: "Não", note: "devolução não postada" } if state == "nao_devolvida"

      stated_value = c.return_shipping&.dig("stated_cost")&.to_f
      stated = stated_value.present?
      cost = c.return_shipping&.dig("seller_cost")
      covered = c.resolution&.dig("applied_coverage") == true
      value = stated_value || cost
      return { key: nil, label: nil, note: "custo do frete ainda não lido" } if value.nil? && c.return_shipping.nil?
      return { key: "nao", label: "Não", amount: 0.0, covered: covered } if value.to_f <= 0

      planned = state == "aguardando"
      { key: planned ? "previsto" : "sim", label: planned ? "Sim (previsto)" : "Sim", amount: value.round(2),
        source: stated ? "mensagem do ML" : "custo do envio de retorno", covered: covered }
    end

    # Texto da mensagem sem HTML (o ML manda <strong>, <br>); anexos só como dados (nome, tipo, tamanho).
    def message(m)
      text = ActionView::Base.full_sanitizer.sanitize(m["message"].to_s.gsub(%r{<br\s*/?>}i, "\n")).to_s
      { sender: m["sender_role"], sender_label: ROLES[m["sender_role"]] || m["sender_role"], receiver: m["receiver_role"],
        receiver_label: ROLES[m["receiver_role"]] || m["receiver_role"],
        date: m["message_date"].presence || m["date_created"], text: CGI.unescapeHTML(text).strip, stage: m["stage"], status: m["status"],
        read_at: m["date_read"], moderation: m["message_moderation"],
        attachments: Array(m["attachments"]).map { |a| a.slice("filename", "original_filename", "type", "size", "date_created") } }
    end

    # Contadores para o botão "A atender" (sempre sobre todas as abertas, sem filtro de período).
    def attention_info
      open = @account.ml_claims.where(status: "opened").select(:id, :status, :stage, :action_responsible, :players).to_a
      { to_attend: open.count { |c| self.class.to_attend?(c) }, open: open.size,
        can_reply: open.count { |c| self.class.reply_targets(c).any? } }
    end

    def import_info
      { total: @account.ml_claims.count, detailed: @account.ml_claims.where.not(details_synced_at: nil).count,
        listed_at: @account.claims_listed_at, full_listed_at: @account.claims_full_listed_at,
        open: @account.ml_claims.open_claims.count }
    end
  end
end
