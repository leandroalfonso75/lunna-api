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
    EXPECTED = { "return_product" => "Devolver o produto", "refund" => "Reembolso", "change_product" => "Troca do produto",
                 "partial_refund" => "Reembolso parcial", "product" => "Receber o produto", "allow_return" => "Permitir devolução" }.freeze

    def self.list(account, params) = new(account, params).list
    def self.detail(account, claim_id) = new(account, {}).detail(claim_id)

    def initialize(account, params)
      @account = account
      @params = params
    end

    def list
      scope = search(@account.ml_claims)
      total = scope.count
      per = PER_PAGES.include?(@params[:per_page].to_i) ? @params[:per_page].to_i : 50
      page = [ @params[:page].to_i, 1 ].max
      claims = scope.order(date_created: :desc, claim_id: :desc).offset((page - 1) * per).limit(per)
        .select(MlClaim.column_names - %w[raw detail messages changes_log evidences devolution reason]).to_a
      orders = orders_for(claims)
      {
        claims: claims.map { |c| row(c, orders[c.claim_id]) },
        total: total, page: page, per_page: per,
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
        .select(:order_id, :shipping_id, :buyer_nickname, :buyer_name, :total_amount, :date_created, :status).to_a
      items = MlOrderItem.where(order_id: orders.map(&:order_id)).group_by(&:order_id)
      thumbs = @account.ml_items.where(item_id: items.values.flatten.map(&:item_id).uniq).pluck(:item_id, :thumbnail).to_h
      claims.to_h do |c|
        o = orders.find { |x| (c.order_id && x.order_id == c.order_id) || (c.resource == "shipment" && x.shipping_id == c.resource_id) }
        line = o && items[o.order_id]&.first
        [ c.claim_id, o && { order_id: o.order_id, buyer_nickname: o.buyer_nickname, buyer_name: o.buyer_name,
                             total: o.total_amount&.to_f, date_created: o.date_created, status: o.status,
                             item: line && { item_id: line.item_id, title: line.title, sku: line.sku, quantity: line.quantity,
                                             thumbnail: thumbs[line.item_id] } } ]
      end
    end

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
        affects_reputation: c.affects_reputation, has_incentive: c.has_incentive,
        resolution: c.resolution && { reason: c.resolution["reason"], benefited: Array(c.resolution["benefited"]),
                                      closed_by: c.resolution["closed_by"], date: c.resolution["date_created"] },
        order: order, detailed: c.details_synced_at.present?,
        link: c.order_id || order ? "https://www.mercadolivre.com.br/vendas/#{order&.dig(:order_id) || c.order_id}/detalhe" : nil
      }
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

    def import_info
      { total: @account.ml_claims.count, detailed: @account.ml_claims.where.not(details_synced_at: nil).count,
        listed_at: @account.claims_listed_at, full_listed_at: @account.claims_full_listed_at,
        open: @account.ml_claims.open_claims.count }
    end
  end
end
