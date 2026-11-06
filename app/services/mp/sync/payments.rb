# Importa os pagamentos do Mercado Pago (aba Repasses): incremental pela data de atualização, a partir da última leitura
# (primeira vez: BACKFILL dias). Guarda as taxas por item de charges_details e o líquido recebido.
module Mp
  module Sync
    module Payments
      BACKFILL = 120.days
      OVERLAP = 2.hours
      WINDOW = 3.days # a busca do MP não garante a ordem entre páginas: cada janela é lida inteira
      MAX_PAGES = 80  # por rodada; janelas que não couberem ficam para a próxima

      Result = Struct.new(:count, :notes, keyword_init: true)

      def self.call(client, account, now: Time.current)
        cursor = account.mp_payments_synced_at ? account.mp_payments_synced_at - OVERLAP : now - BACKFILL
        count = 0
        pages = 0
        while cursor < now
          stop = [ cursor + WINDOW, now ].min
          offset = 0
          loop do
            page = client.payments(begin_date: cursor, end_date: stop, offset: offset)
            pages += 1
            results = Array(page["results"])
            results.each { |p| upsert(account, p) }
            count += results.size
            offset += results.size
            break if results.empty? || offset >= page.dig("paging", "total").to_i
          end
          cursor = stop
          account.update_columns(mp_payments_synced_at: stop)
          break if pages >= MAX_PAGES
        end
        Result.new(count: count, notes: [])
      rescue Mp::Client::Error => e
        Result.new(count: count, notes: [ "Mercado Pago (pagamentos): #{e.message.truncate(160)}" ])
      end

      # Descontos do vendedor (accounts.from = collector), por item de charges_details normalizado:
      #   tarifa = ml_sale_fee + mp_processing_fee + mp_financing_* (é o que o Lunna chama de tarifa de venda);
      #   frete = shp_* (etiqueta cheia; a parte do comprador vem num pagamento à parte, "marketplace_shipment");
      #   cupom = coupon_fee (participação do vendedor no cupom; o Lunna não tinha esse custo);
      #   financing_fee fica de fora: é o juro do parcelamento, pago pelo comprador (financing_transfer) e repassado.
      def self.amounts(charges)
        mine = charges.select { |c| c["from"] == "collector" && c["name"].to_s != "financing_fee" }
        net = ->(c) { c["amount"].to_f - c["refunded"].to_f }
        pick = ->(&rule) { mine.select { |c| rule.call(c["name"].to_s) }.sum(&net).round(2) }
        ml = pick.call { |n| n == "ml_sale_fee" }
        mp = pick.call { |n| n == "mp_processing_fee" }
        fin = pick.call { |n| n.start_with?("mp_financing") }
        shp = pick.call { |n| n.start_with?("shp_") }
        coupon = pick.call { |n| n == "coupon_fee" }
        total = mine.sum(&net).round(2)
        { ml_fee: ml, mp_fee: mp, financing_fee: fin, shipping_fee: shp, coupon_amount: coupon, other_charges: (total - ml - mp - fin - shp - coupon).round(2) }
      end

      def self.normalize(charges)
        Array(charges).map { |c| { "name" => c["name"], "type" => c["type"], "from" => c.dig("accounts", "from"), "to" => c.dig("accounts", "to"),
                                   "amount" => c.dig("amounts", "original"), "refunded" => c.dig("amounts", "refunded") } }
      end

      def self.upsert(account, p)
        charges = normalize(p["charges_details"])
        attrs = {
          ml_account_id: account.id, payment_id: p["id"], order_id: p.dig("order", "id").presence || p["external_reference"].to_s[/\A\d{10,}\z/],
          description: p["description"].to_s.first(255), operation_type: p["operation_type"], status: p["status"], status_detail: p["status_detail"],
          date_created: p["date_created"], date_approved: p["date_approved"], date_last_updated: p["date_last_updated"],
          money_release_date: p["money_release_date"], money_release_status: p["money_release_status"],
          transaction_amount: p["transaction_amount"], refunded_amount: p["transaction_amount_refunded"].to_f,
          net_received: p.dig("transaction_details", "net_received_amount"),
          **amounts(charges), charges: charges,
          created_at: Time.current, updated_at: Time.current
        }
        MpPayment.upsert(attrs, unique_by: %i[ml_account_id payment_id], update_only: attrs.keys - %i[ml_account_id payment_id created_at updated_at])
      end
    end
  end
end
