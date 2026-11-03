# Dados de faturamento do comprador de cada venda (/orders/{id}/billing_info), para a coluna "Cliente" de Vendas
# (pedido do usuário em 03/11/2026). Guarda só nome, tipo e número do documento (CPF/CNPJ) e cidade/UF; descarta
# rua, número, bairro, CEP e complemento. Lê poucos pedidos por rodada (os mais novos primeiro) para não pesar na API.
module Ml
  module Sync
    module BillingInfo
      Result = Struct.new(:count, :notes, :remaining, keyword_init: true)

      def self.pending(account, since: nil)
        scope = account.ml_orders.where(billing_synced_at: nil)
        scope = scope.where("date_created >= ?", since) if since
        scope.order(date_created: :desc)
      end

      def self.call(client, account, limit:, since: nil)
        notes = []
        done = 0
        scope = pending(account, since: since)
        scope.limit(limit).each do |order|
          order.update_columns(slim(client.billing_info(order.order_id)).merge(billing_synced_at: Time.current))
          done += 1
        rescue Ml::Client::NotFound
          order.update_columns(billing_synced_at: Time.current) # sem faturamento: não tenta de novo
        rescue Ml::Client::Error => e
          notes << "faturamento #{order.order_id}: #{e.message}"
          break if e.status == 401 || e.status == 403
        end
        Result.new(count: done, notes: notes.first(5), remaining: scope.count)
      end

      def self.slim(response)
        info = response["billing_info"] || response
        extra = Array(info["additional_info"]).to_h { |x| [ x["type"], x["value"] ] }
        name = [ extra["FIRST_NAME"], extra["LAST_NAME"] ].compact_blank.join(" ").squish.presence || extra["BUSINESS_NAME"].presence
        {
          buyer_name: name&.truncate(150),
          buyer_doc_type: (info["doc_type"].presence || extra["DOC_TYPE"]).to_s.upcase.presence,
          buyer_doc_number: (info["doc_number"].presence || extra["DOC_NUMBER"]).to_s.gsub(/\D/, "").presence,
          buyer_city: extra["CITY_NAME"].presence&.truncate(100),
          buyer_state: (extra["STATE_CODE"].presence || extra["STATE_NAME"].presence)&.to_s&.sub(/\ABR-/, "")&.truncate(40)
        }
      end
    end
  end
end
