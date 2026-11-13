# Variações do mesmo anúncio pai (pedido do usuário em 13/11/2026): no modelo de User Products do ML cada variação (ex.:
# cada tom da base) é um anúncio próprio e o pai é a família (`ml_items.family_id`). Valem só os anúncios da mesma família
# com o mesmo tipo (Clássico/Premium) e fora do catálogo: outro anúncio do mesmo produto (catálogo, outro tipo, outra
# família) não entra.
module Ml
  module ItemVariations
    def self.siblings(account, item_id)
      item = account.ml_items.find_by(item_id: item_id)
      return account.ml_items.none if item.nil? || item.family_id.blank? || item.catalog_listing

      account.ml_items.where(family_id: item.family_id, listing_type_id: item.listing_type_id, catalog_listing: [ false, nil ])
             .where.not(item_id: item_id)
    end

    def self.payload(account, item_id)
      list = siblings(account, item_id).order(:sku).pluck(:item_id, :sku, :title, :status)
      { count: list.size, items: list.map { |id, sku, title, status| { item_id: id, sku: sku, title: title, status: status } } }
    end
  end
end
