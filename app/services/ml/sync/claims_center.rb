# Seção Reclamações: importa TODAS as reclamações da conta no Mercado Livre (pedido do usuário em 03/11/2026), com tudo o
# que a API informa. Somente leitura.
#   1) Lista (/post-purchase/v1/claims/search, vendedor como respondent): a primeira vez, completa (100 por página,
#      desde 2020); depois, só as alteradas (ordenadas por última alteração, até chegar na última leitura) e uma lista
#      completa por dia para pegar o que escapar.
#   2) Detalhes de cada reclamação nova ou alterada (e das abertas a cada hora), poucas por rodada, mais novas primeiro:
#      reclamação completa, detalhe (o que fazer, prazo, quem age), mensagens (texto e anexos como dados; arquivos não
#      são baixados), histórico de situação, ações, resoluções esperadas, evidências, alterações, impacto na reputação,
#      devolução (v2) e o motivo em texto. Parte que o ML recusar fica em detail_errors e não impede o resto.
module Ml
  module Sync
    module ClaimsCenter
      PAGE = 100
      FULL_LIST_EVERY = 24.hours
      REFRESH_OPEN_AFTER = 1.hour
      DETAILS_BATCH = 30
      REASON_TTL = 7.days

      Result = Struct.new(:listed, :detailed, :notes, :remaining, keyword_init: true)

      SUB_RESOURCES = {
        detail: "detail", messages: "messages", status_history: "status_history", actions_history: "actions-history",
        expected_resolutions: "expected-resolutions", evidences: "evidences", changes_log: "changes", reputation: "affects-reputation"
      }.freeze

      def self.call(client, account, details_limit: DETAILS_BATCH)
        notes = []
        listed = list(client, account, notes)
        detailed = details(client, account, details_limit, notes)
        Result.new(listed: listed, detailed: detailed, notes: notes.first(5), remaining: pending(account).count)
      end

      # --- 1) lista ---

      def self.list(client, account, notes)
        full = account.claims_full_listed_at.nil? || account.claims_full_listed_at <= FULL_LIST_EVERY.ago
        since = full ? nil : account.claims_listed_at
        started = Time.current
        count = 0
        offset = 0
        loop do
          page = client.claims_search(account.seller_id, offset: offset, limit: PAGE, sort: full ? "date_created:desc" : "last_updated:desc")
          rows = Array(page["data"])
          break if rows.empty?

          upsert(account, rows)
          count += rows.size
          offset += rows.size
          break if since && rows.any? { |r| r["last_updated"].present? && Time.zone.parse(r["last_updated"]) < since - 1.hour }
          break if offset >= page.dig("paging", "total").to_i
        end
        attrs = { claims_listed_at: started }
        attrs[:claims_full_listed_at] = started if full
        account.update_columns(attrs)
        count
      rescue Ml::Client::Error => e
        notes << "reclamações (lista): #{e.message}"
        count
      end

      def self.upsert(account, rows)
        now = Time.current
        records = rows.map do |c|
          summary(c).merge(ml_account_id: account.id, raw: c, listed_at: now, created_at: now, updated_at: now)
        end
        MlClaim.upsert_all(records, unique_by: %i[ml_account_id claim_id],
                                    update_only: records.first.keys - %i[ml_account_id claim_id created_at updated_at])
      end

      def self.summary(c)
        resource = c["resource"]
        {
          claim_id: c["id"], parent_id: c["parent_id"], resource: resource, resource_id: c["resource_id"],
          order_id: resource == "order" ? c["resource_id"] : nil,
          claim_type: c["type"], stage: c["stage"], status: c["status"], reason_id: c["reason_id"],
          fulfilled: c["fulfilled"], quantity_type: c["quantity_type"], claimed_quantity: c["claimed_quantity"], site_id: c["site_id"],
          date_created: c["date_created"], last_updated: c["last_updated"],
          players: Array(c["players"]), resolution: c["resolution"].presence, related_entities: Array(c["related_entities"])
        }
      end

      # --- 2) detalhes ---

      def self.pending(account)
        account.ml_claims.where(
          "details_synced_at IS NULL OR last_updated > details_synced_at OR (status = 'opened' AND details_synced_at <= ?)",
          REFRESH_OPEN_AFTER.ago
        )
      end

      def self.details(client, account, limit, notes)
        reasons = {}
        done = 0
        pending(account).order(Arel.sql("status = 'opened' DESC, details_synced_at IS NOT NULL, date_created DESC")).limit(limit).each do |claim|
          claim.update_columns(fetch_details(client, claim, reasons).merge(details_synced_at: Time.current, updated_at: Time.current))
          done += 1
        rescue Ml::Client::Error => e
          notes << "reclamação #{claim.claim_id}: #{e.message}"
          break if e.status == 401 || e.status == 403
        end
        done
      end

      def self.fetch_details(client, claim, reasons)
        errors = {}
        full = safe(errors, :claim) { client.claim(claim.claim_id) }
        attrs = full ? summary(full).merge(raw: full) : {}
        SUB_RESOURCES.each do |column, path|
          value = safe(errors, column) { client.claim_sub(claim.claim_id, path) }
          value = value["data"] if column == :changes_log && value.is_a?(Hash)
          attrs[column] = value unless value.nil?
        end
        if (d = attrs[:detail]).is_a?(Hash)
          attrs.merge!(detail_title: d["title"], detail_description: d["description"], detail_problem: d["problem"],
                       action_responsible: d["action_responsible"], due_date: d["due_date"])
        end
        if (r = attrs[:reputation]).is_a?(Hash)
          attrs.merge!(affects_reputation: reputation_flag(r["affects_reputation"]), reputation_status: r["affects_reputation"]&.to_s.presence,
                       has_incentive: reputation_flag(r["has_incentive"]))
        end
        # Devolução: sempre consultada (404 = não há). O ML nem sempre lista "return" em related_entities de reclamação
        # já encerrada, e confiar nisso deixava devoluções entregues/expiradas de fora (corrigido em 03/11/2026).
        attrs[:devolution] = safe(errors, :devolution) { client.claim_return(claim.claim_id) }
        attrs[:return_shipping] = return_shipping(client, attrs[:devolution], claim.ml_account, errors)
        if attrs[:return_shipping] && (stated = stated_freight(attrs[:messages]))
          attrs[:return_shipping] = attrs[:return_shipping].merge("stated_cost" => stated)
        end
        # Custo real do frete da devolução para o vendedor (card Devoluções, 05/11/2026): o ML decide por reclamação
        # (0 = grátis). O custo do envio de retorno (/shipments/{id}/costs) é o valor da etiqueta, não o cobrado.
        if attrs[:devolution].present?
          cost = safe(errors, :return_cost) { client.claim_return_cost(claim.claim_id) }
          attrs.merge!(return_cost: cost["amount"].to_f.round(2), return_cost_at: Time.current) if cost.is_a?(Hash)
        end
        reason_id = (full || {})["reason_id"] || claim.reason_id
        if reason_id.present? && (reason = reason(client, reason_id, reasons))
          attrs.merge!(reason: reason, reason_name: reason["name"], reason_detail: reason["detail"], reason_flow: reason["flow"])
        end
        attrs.merge(detail_errors: errors)
      end

      # Valor do frete da devolução que o ML informa na mensagem ao vendedor ("custo do frete da etiqueta de devolução
      # ... R$ 9,79"): é o que foi cobrado; o custo do envio pode ser maior (subsídio do ML).
      FREIGHT_MSG = /frete da etiqueta de devolu[çc][ãa]o.{0,80}?R\$\s*\**\s*([\d.]+,\d{2})/i

      def self.stated_freight(messages)
        found = Array(messages).filter_map { |m| m.is_a?(Hash) && m["message"].to_s[FREIGHT_MSG, 1] }.first
        found && found.delete(".").tr(",", ".").to_f
      end

      # Frete da devolução: custo do envio de retorno e quanto ficou com o vendedor (ele é o receiver do retorno).
      def self.return_shipping(client, devolution, account, errors)
        shipment = Array(devolution.is_a?(Hash) ? devolution["shipments"] : nil).find { |s| s["type"] == "return" } ||
                   Array(devolution.is_a?(Hash) ? devolution["shipments"] : nil).first
        return nil unless shipment && shipment["shipment_id"]

        costs = safe(errors, :return_shipping) { client.shipment_costs(shipment["shipment_id"]) }
        return nil unless costs

        receiver = costs["receiver"] || {}
        seller_cost = receiver["user_id"].to_s == account.seller_id.to_s ? receiver["cost"].to_f : 0.0
        { "shipment_id" => shipment["shipment_id"], "gross_amount" => costs["gross_amount"], "seller_cost" => seller_cost,
          "receiver" => receiver.slice("user_id", "cost", "save", "compensation"),
          "senders" => Array(costs["senders"]).map { |s| s.slice("user_id", "cost") } }
      end

      # O ML responde affects_reputation como texto ("affected" / "not_affected"); valor desconhecido fica nil (o texto
      # original vai em reputation_status). Nunca converter texto direto para booleano: "not_affected" viraria true.
      def self.reputation_flag(value)
        case value.to_s
        when "affected", "true" then true
        when "not_affected", "false" then false
        end
      end

      # Uma parte que o ML recusa (404 = não existe para esta reclamação) não impede as outras.
      def self.safe(errors, key)
        yield
      rescue Ml::Client::NotFound
        nil
      rescue Ml::Client::Error => e
        # 401 "not available for Claims 1.0": reclamação antiga sem esse recurso; não é falta de permissão (seguir para as próximas)
        raise if (e.status == 401 && !e.message.include?("Claims 1.0")) || (e.status == 403 && key == :claim)

        errors[key.to_s] = e.message.truncate(200)
        nil
      end

      def self.reason(client, reason_id, reasons)
        reasons[reason_id] ||= Rails.cache.fetch([ "ml-claim-reason-full", reason_id ], expires_in: REASON_TTL) do
          client.claim_reason(reason_id)
        end
      rescue Ml::Client::Error
        nil
      end
    end
  end
end
