# Reclamações › Devoluções: nota fiscal de devolução de cada devolução efetivada (pedido do usuário em 13/11/2026).
#   - Full: a última nota do envio da venda no ML (GET /users/{id}/invoices/shipments/{shipping_id}); quando o produto volta,
#     o ML emite a nota "Devolução de mercadorias" (fiscal_data.transaction_type = "devolution") nesse envio.
#   - Agência, Flex e demais: a nota de entrada no Olist (GET /notas?tipo=E), do mesmo comprador (CPF/CNPJ da venda ou,
#     sem documento, o nome), emitida a partir da abertura da reclamação, de preferência com o SKU da venda.
# Somente leitura. Cada devolução sem nota é conferida de novo a cada RECHECK; achada a nota, não é mais consultada.
module Ml
  module Sync
    module ReturnInvoices
      BATCH = 40
      RECHECK = 6.hours
      OLIST_PAGES = 10
      Result = Struct.new(:found, :checked, :notes, keyword_init: true)

      def self.call(client, account, olist: nil)
        notes = []
        claims = pending(account).limit(BATCH).to_a
        return Result.new(found: 0, checked: 0, notes: notes) if claims.empty?

        orders = orders_for(account, claims)
        entries = nil
        found = 0
        claims.each do |claim|
          order = orders[claim.claim_id]
          invoice = nil
          if order
            if order.shipment.to_h["logistic_type"] == "fulfillment"
              invoice = full_invoice(client, account, order, notes)
            else
              entries ||= olist_entries(account, olist, notes)
              invoice = olist_invoice(entries, claim, order)
            end
          end
          found += 1 if invoice
          claim.update_columns(return_invoice: invoice, return_invoice_checked_at: Time.current)
        end
        Result.new(found: found, checked: claims.size, notes: notes)
      end

      # Devoluções efetivadas (o produto voltou) ainda sem nota, conferidas há mais de RECHECK.
      def self.pending(account)
        account.ml_claims.where("devolution->>'status' = ?", "delivered").where(return_invoice: nil)
               .where("return_invoice_checked_at IS NULL OR return_invoice_checked_at < ?", RECHECK.ago)
               .order(Arel.sql("return_invoice_checked_at NULLS FIRST"), date_created: :desc)
      end

      def self.orders_for(account, claims)
        by_order = account.ml_orders.where(order_id: claims.filter_map(&:order_id)).index_by(&:order_id)
        ship_ids = claims.select { |c| c.resource == "shipment" }.map(&:resource_id)
        by_ship = account.ml_orders.where(shipping_id: ship_ids).index_by(&:shipping_id)
        claims.to_h { |c| [ c.claim_id, (c.order_id && by_order[c.order_id]) || (c.resource == "shipment" && by_ship[c.resource_id]) || nil ] }
      end

      def self.full_invoice(client, account, order, notes)
        return nil unless order.shipping_id

        inv = client.invoice_by_shipment(account.seller_id, order.shipping_id)
        return nil unless inv.dig("fiscal_data", "transaction_type") == "devolution"

        build(inv["invoice_number"], inv["invoice_series"], "ml", inv["issued_date"], inv.dig("attributes", "invoice_key"))
      rescue Ml::Client::NotFound
        nil
      rescue Ml::Client::Error => e
        notes << "nota de devolução #{order.order_id}: #{e.message.truncate(120)}"
        nil
      end

      def self.olist_entries(account, olist, notes)
        olist ||= olist_client(account)
        return [] unless olist

        list = []
        OLIST_PAGES.times do |page|
          batch = Array(olist.entry_notes(limit: 100, offset: page * 100)["itens"])
          list.concat(batch)
          break if batch.size < 100
        end
        list
      rescue StandardError => e
        notes << "Olist (notas de entrada): #{e.message.truncate(120)}"
        []
      end

      def self.olist_client(account)
        conn = account.company.olist_connection
        conn && !conn.reauth_required? ? Olist::Client.new(conn) : nil
      end

      def self.olist_invoice(entries, claim, order)
        doc = order.buyer_doc_number.to_s.gsub(/\D/, "")
        name = normalize(order.buyer_name)
        since = claim.date_created.to_date - 1
        skus = MlOrderItem.where(order_id: order.order_id).pluck(:sku).compact
        candidates = entries.select do |n|
          next false unless n["tipo"].to_s == "E"
          next false if n["dataEmissao"].present? && Date.parse(n["dataEmissao"]) < since

          ndoc = n.dig("cliente", "cpfCnpj").to_s.gsub(/\D/, "")
          doc.present? && ndoc.present? ? ndoc == doc : name.present? && normalize(n.dig("cliente", "nome")) == name
        end
        best = candidates.min_by do |n|
          sku_hit = Array(n["itens"]).any? { |i| skus.include?(i["codigo"]) } ? 0 : 1
          [ sku_hit, n["dataEmissao"].to_s ]
        end
        best && build(best["numero"], best["serie"], "olist", best["dataEmissao"], best["chaveAcesso"])
      end

      def self.normalize(text) = I18n.transliterate(text.to_s).downcase.squish.presence

      # "001215-2": número com 6 dígitos e a série.
      def self.build(number, series, source, issued_at, key)
        return nil if number.blank?

        num = number.to_s.gsub(/\D/, "").rjust(6, "0")
        { "number" => num, "series" => series.to_s, "label" => [ num, series.presence ].compact.join("-"), "source" => source,
          "issued_at" => issued_at, "key" => key }
      end
    end
  end
end
