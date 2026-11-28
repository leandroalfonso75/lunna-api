# Anúncios vinculados a um produto, por canal de venda (28/11/2026). Hoje o único canal ligado ao Lunna é o Mercado
# Livre; outro canal entra como mais um adaptador em CHANNELS, sem mudar a tela.
#
# Mercado Livre: o anúncio é ligado ao produto pelo SKU — o SKU do anúncio ou o SKU de uma variação dele (o das linhas
# de venda e o do Full). Anúncio com variações aparece UMA vez (o anúncio pai), mesmo que várias variações do produto
# apontem para ele.
module Catalog
  module ChannelListings
    module_function

    # => [ { key:, name:, connected:, listings: [ { id:, title:, status:, status_label:, url:, thumbnail:, account:, skus:,
    #        variations:, catalog: } ] } ]
    def call(company, product)
      skus = product_skus(product)
      CHANNELS.map { |ch| ch.call(company, skus) }
    end

    def product_skus(product)
      ([ product.sku ] + product.variations.map { |v| v["sku"] }).compact_blank.uniq
    end

    STATUS_LABELS = { "active" => "Ativo", "paused" => "Pausado", "closed" => "Finalizado", "under_review" => "Em revisão",
                      "inactive" => "Inativo" }.freeze

    MERCADO_LIVRE = lambda do |company, skus|
      accounts = company.ml_accounts.to_a
      channel = { key: "mercado_livre", name: "Mercado Livre", connected: accounts.any?, listings: [] }
      next channel if accounts.empty? || skus.empty?

      account_ids = accounts.map(&:id)
      by_item = Hash.new { |h, k| h[k] = Set.new }
      MlItem.where(ml_account_id: account_ids, sku: skus).pluck(:item_id, :sku).each { |id, sku| by_item[id] << sku }
      # variações: o SKU de cada variação vem nas linhas de venda e no Full (o anúncio pai pode ter outro SKU)
      MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id").where(o: { ml_account_id: account_ids })
                 .where(sku: skus).distinct.pluck("ml_order_items.item_id", "ml_order_items.sku").each { |id, sku| by_item[id] << sku }
      if defined?(MlFullReplenishment) && MlFullReplenishment.column_names.include?("seller_sku")
        MlFullReplenishment.where(ml_account_id: account_ids, seller_sku: skus).where.not(item_id: nil)
                           .pluck(:item_id, :seller_sku).each { |id, sku| by_item[id] << sku }
      end
      next channel if by_item.empty?

      nick = accounts.to_h { |a| [ a.id, a.nickname ] }
      items = MlItem.where(item_id: by_item.keys).order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'paused' THEN 1 ELSE 2 END"), :title)
      channel[:listings] = items.map do |i|
        { id: i.item_id, title: i.title, status: i.status, status_label: STATUS_LABELS.fetch(i.status.to_s, i.status.to_s),
          url: i.permalink, thumbnail: i.thumbnail, account: nick[i.ml_account_id], skus: by_item[i.item_id].to_a.sort,
          variations: i.variations_count.to_i, catalog: i.catalog_listing == true }
      end
      channel
    end

    CHANNELS = [ MERCADO_LIVRE ].freeze
  end
end
