# Seção Estoque › Full (pedido do usuário em 14/11/2026): lê as recomendações de reposição do Full de todos os User
# Products do vendedor (GET /marketplace/fbm/sellers/{id}/user-products/replenishment?country=BR, 20 por página) e grava
# em ml_full_replenishments; o que sumiu da lista é apagado. Somente leitura no ML.
module Ml
  module Sync
    module FullReplenishment
      PAGE = 20
      MAX_PAGES = 200
      Result = Struct.new(:count, :notes, keyword_init: true)

      def self.call(client, account, now: Time.current)
        seen = []
        notes = []
        MAX_PAGES.times do |page|
          data = client.full_replenishment(account.seller_id, offset: page * PAGE)
          rows = Array(data["results"])
          rows.each { |r| seen << save(account, r, now) }
          break if rows.size < PAGE || (page + 1) * PAGE >= data.dig("paging", "total").to_i
        end
        account.ml_full_replenishments.where.not(user_product_id: seen.compact).delete_all if seen.any?
        account.update_columns(full_replenishment_synced_at: now)
        Result.new(count: seen.size, notes: notes)
      rescue Ml::Client::Error => e
        notes << "reposição do Full: #{e.message.to_s.truncate(160)}"
        Result.new(count: seen.size, notes: notes)
      end

      def self.save(account, r, now)
        up = r.dig("identifiers", "user_product_id")
        return nil if up.blank?

        stock = r["stock"] || {}
        sales = r["sales"] || {}
        rec = r["recommendation"] || {}
        row = account.ml_full_replenishments.find_or_initialize_by(user_product_id: up)
        row.update!(
          inventory_id: r.dig("identifiers", "inventory_id"), seller_sku: r.dig("identifiers", "seller_sku"),
          tags: Array(r.dig("product", "tags")), total_stock: stock["total_stock"], shipping_urgency: stock["shipping_urgency"],
          minimum_distributable_stock: stock["minimum_distributable_stock"],
          units_30d: Array(sales.dig("sales_totals", "units_sold")).sum { |u| u.values.sum(&:to_i) },
          gmv_30d: Array(sales.dig("sales_totals", "gmv")).sum { |g| g.values.sum(&:to_f) },
          sales_history: Array(sales["sales_history"]).map { |h| h.slice("start_date", "end_date", "units_sold", "days_out_of_stock") },
          recommendation_type: rec["recommendation_type"], suggested_quantity: rec.dig("suggested_quantity", "value"),
          replenishment_deadline: rec["replenishment_deadline"], replenishment_frequency: rec["replenishment_frequency"],
          benefits: Array(r["eligibility_benefits"]), synced_at: now
        )
        up
      end
    end
  end
end
