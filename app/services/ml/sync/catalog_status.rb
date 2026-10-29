# Anúncios de catálogo ativos: se estão ganhando a vitrine do produto, o preço para ganhar e o preço do vencedor
# (/items/{id}/price_to_win). Usado pela seção Promoções (filtro Catálogo).
module Ml
  module Sync
    module CatalogStatus
      Result = Struct.new(:checked, :notes, keyword_init: true)

      def self.call(client, account, item_ids: nil)
        scope = account.ml_items.where(status: "active", catalog_listing: true)
        scope = scope.where(item_id: item_ids) if item_ids
        notes = []
        checked = 0
        scope.pluck(:item_id).each do |id|
          r = client.price_to_win(id)
          account.ml_items.where(item_id: id).update_all(
            catalog_status: r["status"], catalog_price_to_win: r["price_to_win"], catalog_winner_price: r.dig("winner", "price"),
            catalog_reasons: Array(r["reason"]), catalog_checked_at: Time.current
          )
          checked += 1
        rescue Ml::Client::Error => e
          notes << "price_to_win #{id}: #{e.message.truncate(150)}"
        end
        Result.new(checked: checked, notes: notes)
      end
    end
  end
end
