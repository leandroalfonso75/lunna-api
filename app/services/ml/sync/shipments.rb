# Envio de cada pedido (/shipments/{id} + /shipments/{id}/costs). Guarda só o que a seção
# Vendas mostra e descarta endereço, telefone e nome do comprador (dados pessoais).
# Pedidos com envio já entregue/cancelado/devolvido há mais de 2 dias não são relidos.
module Ml
  module Sync
    module Shipments
      FINAL_STATUSES = %w[delivered cancelled not_delivered returned].freeze
      REFRESH_AFTER = 2.hours

      Result = Struct.new(:count, :notes, :remaining, keyword_init: true)

      # Pedidos que precisam de envio (sem envio lido ou com envio ainda em andamento), os mais
      # novos primeiro. `limit` quebra o trabalho em rodadas curtas.
      def self.pending(account, since: nil)
        scope = account.ml_orders.where.not(shipping_id: nil)
        scope = scope.where("date_created >= ?", since) if since
        scope.where(
          "shipment IS NULL OR (COALESCE(shipment->>'status', '') NOT IN (?) AND shipment_synced_at <= ?)",
          FINAL_STATUSES, REFRESH_AFTER.ago
        ).order(date_created: :desc)
      end

      def self.call(client, account, limit:, since: nil)
        notes = []
        done = 0
        scope = pending(account, since: since)
        orders = scope.limit(limit).to_a

        orders.each do |order|
          order.update_columns(shipment: build(client, order.shipping_id), shipment_synced_at: Time.current)
          done += 1
        rescue Ml::Client::NotFound
          # envio apagado/sem acesso: marca como lido para não tentar de novo a cada rodada
          order.update_columns(shipment: { "status" => "unavailable" }, shipment_synced_at: Time.current)
        rescue Ml::Client::Error => e
          notes << "envio #{order.shipping_id}: #{e.message}"
          break if e.status == 401 || e.status == 403
        end

        Result.new(count: done, notes: notes.first(5), remaining: scope.count)
      end

      def self.build(client, shipping_id)
        shipment = client.shipment(shipping_id)
        costs = begin
          client.shipment_costs(shipping_id)
        rescue Ml::Client::Error
          nil
        end
        slim(shipment, costs)
      end

      def self.slim(shipment, costs)
        option = shipment["shipping_option"] || {}
        sender = costs && Array(costs["senders"]).first

        {
          "id" => shipment["id"],
          "status" => shipment["status"],
          "substatus" => shipment["substatus"],
          "logistic_type" => shipment["logistic_type"],
          "mode" => shipment["mode"],
          "tracking_number" => shipment["tracking_number"],
          "tracking_method" => shipment["tracking_method"],
          "date_created" => shipment["date_created"],
          "last_updated" => shipment["last_updated"],
          "status_history" => shipment["status_history"],
          "substatus_history" => Array(shipment["substatus_history"]).first(20),
          "base_cost" => shipment["base_cost"],
          "order_cost" => shipment["order_cost"],
          "method_name" => option["name"],
          "delivery_type" => option["delivery_type"],
          "buyer_cost" => option["cost"],
          "list_cost" => option["list_cost"],
          "estimated_delivery" => option.dig("estimated_delivery_final", "date") || option.dig("estimated_delivery_time", "date"),
          "estimated_delivery_limit" => option.dig("estimated_delivery_limit", "date"),
          "destination_city" => shipment.dig("receiver_address", "city", "name"),
          "destination_state" => shipment.dig("receiver_address", "state", "name"),
          "seller_cost" => sender && sender["cost"],
          "seller_discounts" => sender && sender["discounts"],
          "buyer_paid" => costs&.dig("receiver", "cost"),
          "gross_amount" => costs && costs["gross_amount"]
        }
      end
    end
  end
end
