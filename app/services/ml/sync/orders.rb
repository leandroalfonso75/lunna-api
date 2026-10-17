# Etapa 4 (SPEC 4): pedidos do vendedor desde `from` (o Run decide 62 ou 4
# dias). Sequencial (a paginação por offset é inerentemente sequencial).
# Grava todos os status — as métricas do painel filtram "paid" depois
# (A4). Linhas do mesmo pedido e mesmo anúncio são somadas (quantidade
# somada; preço e tarifa como média ponderada pela quantidade); dedup por
# chave acontece naturalmente por serem acumuladas num Hash antes do upsert.
module Ml
  module Sync
    module Orders
      PAGE_SIZE = 50
      # ponytail: teto de ~10 mil pedidos por janela (offset 9.950); quebrar
      # em janelas de 7 dias se uma conta passar disso.
      MAX_OFFSET = 9_950
      UPSERT_BATCH_SIZE = 200

      Result = Struct.new(:order_ids, :notes, :ok, keyword_init: true)

      def self.call(client, account, from:)
        orders = {}
        order_items = {}
        offset = 0
        notes = []
        ok = true

        while offset <= MAX_OFFSET
          begin
            page = client.orders_search(account.seller_id, from: from, offset: offset)
          rescue Ml::Client::Error => e
            notes << "pedidos offset #{offset}: #{e.message}"
            ok = false
            break
          end

          results = page["results"] || []
          results.each do |order|
            orders[order["id"]] = order
            (order["order_items"] || []).each { |line| accumulate(order_items, order["id"], line) }
          end

          total = page.dig("paging", "total") || 0
          break if results.size < PAGE_SIZE || offset + PAGE_SIZE >= total

          offset += PAGE_SIZE
        end

        save(account, orders, order_items)

        Result.new(order_ids: orders.keys, notes: notes, ok: ok)
      end

      def self.accumulate(order_items, order_id, line)
        item_id = line.dig("item", "id")
        return if item_id.blank?

        entry = order_items[[ order_id, item_id ]] ||= {
          quantity: 0, amount: 0.0, fee_amount: 0.0,
          title: line.dig("item", "title"),
          sku: line.dig("item", "seller_sku").presence || line.dig("item", "seller_custom_field").presence,
          listing_type_id: line["listing_type_id"],
          variation_id: line.dig("item", "variation_id")
        }
        quantity = line["quantity"].to_i
        entry[:quantity] += quantity
        entry[:amount] += line["unit_price"].to_f * quantity
        entry[:fee_amount] += line["sale_fee"].to_f * quantity
      end
      private_class_method :accumulate

      def self.save(account, orders, order_items)
        order_rows = orders.values.map do |order|
          {
            order_id: order["id"],
            ml_account_id: account.id,
            status: order["status"],
            date_created: order["date_created"],
            date_closed: order["date_closed"],
            total_amount: order["total_amount"],
            paid_amount: order["paid_amount"],
            payload: order,
            shipping_id: order.dig("shipping", "id"),
            pack_id: order["pack_id"],
            buyer_id: order.dig("buyer", "id"),
            buyer_nickname: order.dig("buyer", "nickname"),
            synced_at: Time.current
          }
        end

        item_rows = order_items.filter_map do |(order_id, item_id), entry|
          next if entry[:quantity].zero?

          {
            order_id: order_id,
            item_id: item_id,
            quantity: entry[:quantity],
            unit_price: (entry[:amount] / entry[:quantity]).round(2),
            sale_fee: (entry[:fee_amount] / entry[:quantity]).round(2),
            title: entry[:title],
            sku: entry[:sku],
            listing_type_id: entry[:listing_type_id],
            variation_id: entry[:variation_id]
          }
        end

        order_rows.each_slice(UPSERT_BATCH_SIZE) { |batch| MlOrder.upsert_all(batch, unique_by: :order_id) }
        item_rows.each_slice(UPSERT_BATCH_SIZE) { |batch| MlOrderItem.upsert_all(batch) }
      end
      private_class_method :save
    end
  end
end
