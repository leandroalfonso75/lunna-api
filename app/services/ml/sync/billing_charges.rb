# Extrato de faturamento do Mercado Livre (cobranças e bonificações da conta), por período de faturamento:
# GET /billing/integration/periods/key/{KEY}/group/ML/details (document_type BILL, 1000 por página, limite do ML de
# 5 chamadas por minuto). Guarda cada linha em ml_billing_charges ligada à venda (sales_info) e ao envio
# (shipping_info), para o card Devoluções (frete de envio retido, frete de devolução, outras cobranças).
# Lê o período aberto e o anterior, uma vez por dia (o ML diz que o extrato não muda durante o dia).
module Ml
  module Sync
    module BillingCharges
      Result = Struct.new(:count, :notes, keyword_init: true)
      EVERY = 24.hours
      PAGE = 1000
      PERIODS = 2
      PAUSE = 13 # segundos entre páginas: 5 chamadas por minuto

      def self.due?(account) = account.billing_synced_at.nil? || account.billing_synced_at <= EVERY.ago

      def self.call(client, account, sleeper: ->(s) { sleep(s) }, periods: PERIODS)
        notes = []
        count = 0
        keys = client.billing_periods(limit: periods).map { |p| p["key"] }
        keys.each do |key|
          offset = 0
          loop do
            page = client.billing_details(key, limit: PAGE, offset: offset)
            rows = Array(page["results"])
            rows.each { |row| count += 1 if upsert(account, key, row) }
            offset += PAGE
            break if rows.empty? || offset >= page["total"].to_i

            sleeper.call(PAUSE)
          end
          sleeper.call(PAUSE)
        end
        account.update_columns(billing_synced_at: Time.current)
        Result.new(count: count, notes: notes)
      rescue Ml::Client::Error => e
        notes << "faturamento: #{e.message.truncate(160)}"
        Result.new(count: count, notes: notes)
      end

      def self.upsert(account, key, row)
        ci = row["charge_info"] || {}
        return false if ci["detail_id"].blank?

        # sales_info e items_info vêm como lista (carrinho: várias vendas numa linha); guardamos a primeira venda e o
        # primeiro anúncio nas colunas e tudo em raw. shipping_info é um hash (shipping_id em texto).
        sale = Array(row["sales_info"]).first || {}
        ship = row["shipping_info"].is_a?(Hash) ? row["shipping_info"] : {}
        item = Array(row["items_info"]).first || {}
        attrs = {
          ml_account_id: account.id, detail_id: ci["detail_id"], period_key: key,
          detail_type: ci["detail_type"], detail_sub_type: ci["detail_sub_type"], transaction_detail: ci["transaction_detail"].to_s.first(255),
          amount: ci["detail_amount"], currency_id: row.dig("currency_info", "currency_id"),
          order_id: first_present(sale, %w[order_id]),
          shipment_id: first_present(ship, %w[shipping_id shipment_id]).to_s[/\A\d+\z/]&.to_i,
          item_id: first_present(item, %w[item_id]),
          charged_at: ci["creation_date_time"], raw: row, updated_at: Time.current
        }
        MlBillingCharge.upsert(attrs.merge(created_at: Time.current), unique_by: %i[ml_account_id detail_id],
                               update_only: %i[period_key detail_type detail_sub_type transaction_detail amount currency_id order_id shipment_id item_id charged_at raw])
        true
      end

      def self.first_present(hash, keys)
        keys.each { |k| v = hash[k]; return v if v.present? }
        nil
      end
      private_class_method :first_present
    end
  end
end
