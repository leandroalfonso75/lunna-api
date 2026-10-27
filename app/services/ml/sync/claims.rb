# Reclamações/mediações de cada venda (/post-purchase/v1/claims/{id}): cancelamento pelo comprador,
# reclamação e devolução, com o motivo em texto (/claims/reasons/{id}), o resultado e a devolução
# (/post-purchase/v2/claims/{id}/returns). Guarda só o resumo que a seção Vendas mostra.
# Relida quando o pedido muda depois da última leitura ou enquanto alguma reclamação está aberta.
module Ml
  module Sync
    module Claims
      REFRESH_OPEN_AFTER = 2.hours
      REASON_TTL = 7.days

      Result = Struct.new(:count, :notes, :remaining, keyword_init: true)

      def self.pending(account, since: nil)
        scope = account.ml_orders.where("jsonb_array_length(COALESCE(payload->'mediations', '[]'::jsonb)) > 0")
        scope = scope.where("date_created >= ?", since) if since
        scope.where(
          "claims_synced_at IS NULL OR (payload->>'last_updated')::timestamptz > claims_synced_at " \
          "OR (claims @> '[{\"status\":\"opened\"}]' AND claims_synced_at <= ?)",
          REFRESH_OPEN_AFTER.ago
        ).order(date_created: :desc)
      end

      def self.call(client, account, limit:, since: nil)
        notes = []
        done = 0
        scope = pending(account, since: since)
        reasons = {}

        scope.limit(limit).each do |order|
          ids = Array(order.payload["mediations"]).filter_map { |m| m["id"] }
          order.update_columns(claims: ids.map { |id| build(client, id, reasons) }, claims_synced_at: Time.current)
          done += 1
        rescue Ml::Client::Error => e
          notes << "reclamação do pedido #{order.order_id}: #{e.message}"
          break if e.status == 401 || e.status == 403
        end

        Result.new(count: done, notes: notes.first(5), remaining: scope.count)
      end

      def self.build(client, claim_id, reasons = {})
        claim = client.claim(claim_id)
      rescue Ml::Client::NotFound
        { "id" => claim_id, "status" => "unavailable" }
      else
        slim(claim, reason(client, claim["reason_id"], reasons), devolution(client, claim))
      end

      def self.reason(client, reason_id, reasons)
        return nil if reason_id.blank?

        reasons[reason_id] ||= Rails.cache.fetch([ "ml-claim-reason", reason_id ], expires_in: REASON_TTL) do
          client.claim_reason(reason_id).slice("id", "name", "detail", "flow")
        end
      rescue Ml::Client::Error
        nil
      end

      def self.devolution(client, claim)
        return nil unless Array(claim["related_entities"]).include?("return")

        client.claim_return(claim["id"])
      rescue Ml::Client::NotFound
        nil
      end

      def self.slim(claim, reason, devolution)
        resolution = claim["resolution"] || {}
        {
          "id" => claim["id"],
          "type" => claim["type"],
          "stage" => claim["stage"],
          "status" => claim["status"],
          "reason_id" => claim["reason_id"],
          "reason" => reason && reason["detail"],
          "reason_flow" => reason && reason["flow"],
          "opened_by" => Array(claim["players"]).find { |p| p["role"] == "complainant" }&.dig("type"),
          "date_created" => claim["date_created"],
          "last_updated" => claim["last_updated"],
          "resolution" => resolution.presence && resolution.slice("reason", "benefited", "closed_by", "applied_coverage", "date_created"),
          "return" => devolution && {
            "status" => devolution["status"], "subtype" => devolution["subtype"], "status_money" => devolution["status_money"],
            "date_created" => devolution["date_created"], "refund_at" => devolution["refund_at"],
            "shipments" => Array(devolution["shipments"]).map { |s| s.slice("status", "type", "tracking_number") }
          }
        }
      end
    end
  end
end
