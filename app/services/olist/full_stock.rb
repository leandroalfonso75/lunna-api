# Liga o estoque do Full (lido do Mercado Livre) ao produto do Olist pelo SKU:
# o SKU do Olist é o mesmo do anúncio no ML (seller_custom_field / SELLER_SKU).
# Um estoque Full compartilhado por vários anúncios do mesmo SKU conta uma vez só.
module Olist
  class FullStock
    Info = Struct.new(:available, :not_available, :total, :listings, :synced_at, keyword_init: true)

    # => { "SKU" => Info } só para SKUs com anúncio Full e estoque já lido.
    def self.for_skus(company, skus)
      new(company).for_skus(skus)
    end

    def initialize(company)
      @company = company
    end

    def for_skus(skus)
      skus = skus.compact_blank.uniq
      return {} if skus.empty?

      refs_by_sku = collect_refs(skus)
      return {} if refs_by_sku.empty?

      stocks = MlFullStock.where(ml_account_id: refs_by_sku.values.flatten(1).map(&:first).uniq,
        inventory_id: refs_by_sku.values.flatten(1).map(&:last).uniq).index_by { |s| [ s.ml_account_id, s.inventory_id ] }

      refs_by_sku.filter_map do |sku, refs|
        found = refs.filter_map { |key| stocks[key] }
        next if found.empty?

        [ sku, Info.new(
          available: found.sum(&:available_units), not_available: found.sum(&:not_available_units),
          total: found.sum(&:total_units), listings: refs.size, synced_at: found.map(&:synced_at).min
        ) ]
      end.to_h
    end

    private

    # sku => [[ml_account_id, inventory_id], ...] sem repetir o mesmo inventory.
    def collect_refs(skus)
      by_sku = Hash.new { |hash, key| hash[key] = [] }

      MlItem.joins(:ml_account)
        .where(ml_accounts: { company_id: @company.id }, logistic_type: "fulfillment", status: %w[active paused])
        .where("ml_items.sku IN (:skus) OR ml_items.inventory_refs @> ANY (ARRAY[:refs]::jsonb[])",
          skus: skus, refs: skus.map { |sku| [ { sku: sku } ].to_json })
        .pluck(:ml_account_id, :sku, :inventory_refs).each do |account_id, item_sku, refs|
          refs.each do |ref|
            sku = ref["sku"].presence || item_sku
            next unless skus.include?(sku) && ref["inventory_id"].present?

            by_sku[sku] << [ account_id, ref["inventory_id"] ]
          end
        end

      by_sku.transform_values(&:uniq)
    end
  end
end
