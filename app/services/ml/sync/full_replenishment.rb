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
        seen += legacy(client, account, now, notes) if seen.any?
        account.ml_full_replenishments.where.not(user_product_id: seen.compact).delete_all if seen.any?
        account.update_columns(full_replenishment_synced_at: now)
        Result.new(count: seen.size, notes: notes)
      rescue Ml::Client::Error => e
        notes << "reposição do Full: #{e.message.to_s.truncate(160)}"
        Result.new(count: seen.size, notes: notes)
      end

      # Anúncios do formato antigo (com variações, sem User Product) não vêm na API de reposição (correção de 14/11/2026:
      # MLB2729901870, SKUs LS-SC13-DIF-110/220, ficava fora). Cada estoque Full que não veio na lista vira uma linha
      # própria (user_product_id = "INV:<inventory_id>"), com o anúncio, a variação (lida de GET /items/{id}), o SKU da
      # variação (o vendido nela ou o SELLER_SKU dela), o estoque Full e as vendas de 30 dias; sem recomendação do ML.
      def self.legacy(client, account, now, notes)
        covered = account.ml_full_replenishments.where(source: "ml").where.not(inventory_id: nil).pluck(:inventory_id).to_set
        stocks = MlFullStock.where(ml_account_id: account.id).where.not(inventory_id: covered.to_a).index_by(&:inventory_id)
        return [] if stocks.empty?

        items = account.ml_items.where("inventory_refs::text ~ ?", stocks.keys.map { |k| Regexp.escape(k) }.join("|")).to_a
        ups = []
        items.each do |item|
          body = client.item_full(item.item_id)
          vars = Array(body["variations"])
          refs = vars.any? ? vars.map { |v| [ v["inventory_id"], v ] } : [ [ body["inventory_id"], nil ] ]
          refs.each do |inv, v|
            stock = stocks[inv]
            next unless stock

            ups << save_legacy(account, item, inv, v, stock, now)
          end
        rescue Ml::Client::Error => e
          notes << "estoque Full #{item.item_id}: #{e.message.to_s.truncate(100)}"
        end
        ups.compact.uniq
      end

      def self.save_legacy(account, item, inv, v, stock, now)
        up = "INV:#{inv}"
        vid = v && v["id"]
        sold = MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
                          .where(o: { ml_account_id: account.id }).where.not(o: { status: %w[cancelled invalid] })
                          .where(item_id: item.item_id).then { |q| vid ? q.where(variation_id: vid) : q }
        recent = sold.where("o.date_created >= ?", 30.days.ago)
        sku = sold.where.not(sku: [ nil, "" ]).group(:sku).order(Arel.sql("COUNT(*) DESC")).limit(1).pluck(:sku).first ||
              Array(v && v["attributes"]).find { |a| a["id"] == "SELLER_SKU" }&.dig("value_name") || item.sku
        label = Array(v && v["attribute_combinations"]).filter_map { |a| a["value_name"].presence }.join(" · ").presence
        row = account.ml_full_replenishments.find_or_initialize_by(user_product_id: up)
        row.update!(source: "legacy", inventory_id: inv, seller_sku: sku, item_id: item.item_id, variation_label: label,
                    tags: [ "legacy_listing" ], total_stock: stock.available_units, shipping_urgency: nil, minimum_distributable_stock: nil,
                    units_30d: recent.sum(:quantity), gmv_30d: recent.sum("ml_order_items.unit_price * ml_order_items.quantity"),
                    sales_history: [], recommendation_type: nil, suggested_quantity: nil, replenishment_deadline: nil,
                    replenishment_frequency: nil, benefits: [], synced_at: now)
        up
      end

      def self.save(account, r, now)
        up = r.dig("identifiers", "user_product_id")
        return nil if up.blank?

        stock = r["stock"] || {}
        sales = r["sales"] || {}
        rec = r["recommendation"] || {}
        row = account.ml_full_replenishments.find_or_initialize_by(user_product_id: up)
        row.update!(
          source: "ml", inventory_id: r.dig("identifiers", "inventory_id"), seller_sku: r.dig("identifiers", "seller_sku"),
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
