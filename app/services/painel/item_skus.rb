# SKUs de cada anúncio (pedido do usuário em 08/11/2026, Ads › Análise): o do anúncio, os das variações (inventory_refs)
# e os vendidos nele (linhas de pedido), sem repetir. Sempre completos: a tela nunca abrevia SKU.
module Painel
  module ItemSkus
    def self.for(account, item_ids)
      ids = Array(item_ids).compact.uniq
      return {} if ids.empty?

      map = Hash.new { |h, k| h[k] = [] }
      account.ml_items.where(item_id: ids).pluck(:item_id, :sku, :inventory_refs).each do |id, sku, refs|
        map[id] << sku
        Array(refs).each { |r| map[id] << r["sku"] }
      end
      account.item_metrics.where(item_id: ids).pluck(:item_id, :sku).each { |id, sku| map[id] << sku }
      MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
                 .where(o: { ml_account_id: account.id }).where(item_id: ids).distinct.pluck(:item_id, :sku)
                 .each { |id, sku| map[id] << sku }
      ids.to_h { |id| [ id, map[id].map { |s| s.to_s.strip }.reject(&:blank?).uniq ] }
    end

    # Anúncios da conta que têm algum desses SKUs (no anúncio, nas variações ou nas vendas).
    def self.items_with_skus(account, skus)
      list = Array(skus).map(&:to_s).reject(&:blank?).uniq
      return [] if list.empty?

      ids = account.ml_items.where(sku: list).pluck(:item_id)
      ids += account.ml_items.where("inventory_refs @> ANY (ARRAY[?]::jsonb[])", list.map { |s| [ { sku: s } ].to_json }).pluck(:item_id)
      ids += account.item_metrics.where(sku: list).pluck(:item_id)
      ids += MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
                        .where(o: { ml_account_id: account.id }).where(sku: list).distinct.pluck(:item_id)
      ids.uniq
    end

    # Acrescenta `items: [{ item_id:, skus: [] }]` a cada entrada que tem item_ids.
    def self.attach!(account, entries)
      entries = Array(entries)
      skus = self.for(account, entries.flat_map { |e| Array(e[:item_ids]) })
      entries.each { |e| e[:items_skus] = Array(e[:item_ids]).map { |id| { item_id: id, skus: skus[id] || [] } } }
    end
  end
end
