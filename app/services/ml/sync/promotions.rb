# Seção Promoções: lê a Central de Promoções do Mercado Livre (somente leitura).
#   1. promoções da conta (/seller-promotions/users/{id}) → ml_promotions
#   2. ofertas de cada anúncio ativo (/seller-promotions/items/{id}) → ml_promotion_offers, trocadas por anúncio
#   3. tarifa do ML no preço de cada oferta (/sites/MLB/listing_prices, guardada em cache por categoria, tipo e preço)
# Anúncio cuja leitura falhou mantém as ofertas da leitura anterior.
module Ml
  module Sync
    module Promotions
      THREADS = 3
      FEE_TTL = 3.days

      Result = Struct.new(:promotions, :items, :offers, :notes, keyword_init: true)

      def self.call(client, account, item_ids: nil)
        notes = []
        promotions = sync_promotions(client, account, notes)

        items = account.ml_items.where(status: "active")
        items = items.where(item_id: item_ids) if item_ids
        items = items.to_a
        fetched = Parallel.map(items, threads: THREADS) { |item| offers_for(client, item) }

        now = Time.current
        rows = []
        done = []
        items.zip(fetched).each do |item, (status, value)|
          if status == :error
            notes << "promoções de #{item.item_id}: #{value.message}"
            next
          end
          done << item.item_id
          value.each { |offer| rows << record(account, item.item_id, offer, now) }
        end

        MlPromotionOffer.transaction do
          MlPromotionOffer.where(ml_account_id: account.id, item_id: done).delete_all
          rows.each_slice(500) { |batch| MlPromotionOffer.insert_all(batch) }
        end
        account.update_columns(promotions_synced_at: now) if item_ids.nil?

        Result.new(promotions: promotions, items: done.size, offers: rows.size, notes: notes.first(5))
      end

      def self.sync_promotions(client, account, notes)
        results = Array(client.seller_promotions(account.seller_id)["results"])
        now = Time.current
        rows = results.filter_map do |p|
          next if p["id"].blank?

          { ml_account_id: account.id, promotion_id: p["id"], promotion_type: p["type"], sub_type: p["sub_type"],
            name: p["name"], status: p["status"], start_date: p["start_date"], finish_date: p["finish_date"],
            deadline_date: p["deadline_date"], payload: p, synced_at: now, created_at: now, updated_at: now }
        end
        MlPromotion.transaction do
          MlPromotion.where(ml_account_id: account.id).where.not(promotion_id: rows.map { |r| r[:promotion_id] }).delete_all
          MlPromotion.upsert_all(rows, unique_by: :index_ml_promotions_unique, update_only: %i[promotion_type sub_type name status start_date finish_date deadline_date payload synced_at]) if rows.any?
        end
        rows.size
      rescue Ml::Client::Error => e
        notes << "promoções da conta: #{e.message}"
        0
      end

      # Ofertas do anúncio, cada uma com a tarifa do ML no preço que conta para a margem.
      def self.offers_for(client, item)
        Array(client.item_promotions(item.item_id)).map do |offer|
          price = reference_price(offer)
          offer.merge("_fees" => price ? fee_at(client, item, price) : nil)
        end
      rescue Ml::Client::NotFound
        []
      end

      # Preço que define a tarifa: o da oferta (fixo ou já ativo) ou o maior permitido na faixa.
      def self.reference_price(offer)
        [ offer["price"], offer["max_discounted_price"] ].map(&:to_f).find(&:positive?)
      end

      def self.fee_at(client, item, price)
        return nil if item.category_id.blank? || item.listing_type_id.blank?

        Rails.cache.fetch([ "ml-listing-fee", item.category_id, item.listing_type_id, price.round(2) ], expires_in: FEE_TTL) do
          data = client.listing_prices(price: price, listing_type_id: item.listing_type_id, category_id: item.category_id)
          data = data.first if data.is_a?(Array)
          details = data["sale_fee_details"] || {}
          { "price" => price.round(2), "sale_fee" => data["sale_fee_amount"].to_f, "percentage_fee" => details["percentage_fee"].to_f,
            "fixed_fee" => details["fixed_fee"].to_f, "financing" => details["financing_add_on_fee"].to_f }
        end
      rescue Ml::Client::Error
        nil
      end

      def self.record(account, item_id, offer, now)
        {
          ml_account_id: account.id, item_id: item_id, promotion_id: offer["id"], promotion_type: offer["type"],
          sub_type: offer["sub_type"], name: offer["name"].presence, status: offer["status"],
          price: positive(offer["price"]), original_price: positive(offer["original_price"]),
          min_price: positive(offer["min_discounted_price"]), max_price: positive(offer["max_discounted_price"]),
          max_top_price: positive(offer["max_top_discounted_price"]), suggested_price: positive(offer["suggested_discounted_price"]),
          fixed_amount: positive(offer["fixed_amount"]), meli_percentage: offer["meli_percentage"], seller_percentage: offer["seller_percentage"],
          start_date: offer["start_date"], finish_date: offer["finish_date"] || offer["end_date"],
          fees: offer["_fees"], payload: offer.except("_fees"), synced_at: now, created_at: now, updated_at: now
        }
      end

      def self.positive(value) = value.to_f.positive? ? value : nil
    end
  end
end
