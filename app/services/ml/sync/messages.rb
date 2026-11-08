# Seção Mensagens: conversas de pós-venda (tag post_sale), sem marcar como lidas (mark_as_read=false).
# O ML não lista todas as conversas: a cada rodada o Lunna relê
#   1. as que têm mensagem não lida (/messages/unread);
#   2. as conversas abertas com mensagem nos últimos 7 dias;
#   3. as vendas dos últimos 60 dias ainda não conferidas (ou conferidas há mais de 12 h, se recentes), BATCH por rodada.
module Ml
  module Sync
    module Messages
      BATCH = 80
      WINDOW = 60.days
      RECHECK_RECENT = 12.hours
      RECENT = 10.days
      Result = Struct.new(:count, :notes, keyword_init: true)

      def self.call(client, account, batch: BATCH, now: Time.current)
        notes = []
        packs = unread_packs(client, account, notes)
        packs += account.ml_conversations.where(status: "active").where("last_message_at > ?", now - 7.days).pluck(:pack_id)
        orders = pending_orders(account, now).limit(batch).to_a
        packs += orders.map { |o| o.pack_id || o.order_id }
        count = 0
        packs.uniq.each do |pack|
          count += 1 if refresh(client, account, pack)
        rescue Ml::Client::Error => e
          notes << "mensagens #{pack}: #{e.message.to_s.truncate(120)}"
          break if e.status == 401 || e.status == 403
        end
        MlOrder.where(order_id: orders.map(&:order_id)).update_all(messages_checked_at: now) if orders.any?
        Result.new(count: count, notes: notes.first(3))
      end

      def self.pending_orders(account, now)
        account.ml_orders.where("date_created > ?", now - WINDOW)
          .where("messages_checked_at IS NULL OR (date_created > ? AND messages_checked_at < ?)", now - RECENT, now - RECHECK_RECENT)
          .order(Arel.sql("messages_checked_at IS NOT NULL, date_created DESC"))
      end

      def self.unread_packs(client, account, notes)
        data = client.messages_unread
        Array(data["results"]).filter_map { |r| r["resource"].to_s[%r{/packs/(\d+)/}, 1]&.to_i }
      rescue Ml::Client::Error => e
        notes << "mensagens não lidas: #{e.message.to_s.truncate(120)}"
        []
      end

      # Relê a conversa; grava só se tem mensagem. Devolve true quando há conversa.
      def self.refresh(client, account, pack)
        data = client.pack_messages(account.seller_id, pack)
        msgs = Array(data["messages"])
        total = data.dig("paging", "total").to_i
        offset = msgs.size
        while offset < total && offset < 200
          more = Array(client.pack_messages(account.seller_id, pack, offset: offset)["messages"])
          break if more.empty?

          msgs += more
          offset += more.size
        end
        existing = account.ml_conversations.find_by(pack_id: pack)
        return false if msgs.empty? && existing.nil?

        save(account, pack, data["conversation_status"] || {}, msgs, data["seller_max_length"] || data["seller_max_message_length"])
        true
      end

      def self.save(account, pack, conv, msgs, max_length)
        seller = account.seller_id.to_i
        list = msgs.map do |m|
          { "id" => m["id"], "from" => m.dig("from", "user_id"), "to" => m.dig("to", "user_id"), "text" => m["text"],
            "date" => m.dig("message_date", "created") || m.dig("message_date", "received"), "read" => m.dig("message_date", "read"),
            "status" => m["status"], "moderation" => m.dig("message_moderation", "status"),
            "attachments" => Array(m["message_attachments"]).map { |a| a.slice("filename", "original_filename", "type", "size") } }
        end.sort_by { |m| m["date"].to_s }
        last = list.last
        # comprador = o da venda (mensagens do assistente do ML vêm de outro usuário); sem venda, a outra ponta da conversa
        order_buyer = account.ml_orders.where(pack_id: pack).or(account.ml_orders.where(order_id: pack)).where.not(buyer_id: nil).pick(:buyer_id)
        buyer = order_buyer || list.map { |m| m["from"] == seller ? m["to"] : m["from"] }.compact.first
        row = account.ml_conversations.find_or_initialize_by(pack_id: pack)
        row.update!(
          buyer_id: buyer, status: conv["status"], substatus: conv["substatus"], claim_ids: Array(conv["claim_ids"]),
          messages: list, messages_count: list.size, unread_count: list.count { |m| m["from"] != seller && m["read"].nil? },
          last_message_at: last && last["date"], last_from: last && (last["from"] == seller ? "seller" : "buyer"),
          seller_max_length: max_length, checked_at: Time.current
        )
      end
    end
  end
end
