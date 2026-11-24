# Anúncios › "Editar anúncios selecionados" (pedido do usuário em 24/11/2026): edita um anúncio só, ou vários desde que
# tenham os mesmos SKUs (ex.: o Clássico e o Premium do mesmo produto). SKUs de cada anúncio = o do anúncio e os das
# variações (inventory_refs), sem as vendas. O primeiro selecionado é o principal: a tela lê e sugere a partir dele e a
# publicação vale também para os outros (also_item_ids).
module Painel
  class BulkEditGroup
    MAX_ITEMS = 20
    Result = Struct.new(:ok, :message, :primary, :others, :skus, keyword_init: true) do
      def as_json(*) = { ok: ok, message: message, primary: primary, others: others, skus: skus }
    end

    def self.call(account, item_ids) = new(account, item_ids).call

    def initialize(account, item_ids)
      @account = account
      @ids = Array(item_ids).map(&:to_s).reject(&:blank?).uniq
    end

    def call
      return fail("Selecione ao menos um anúncio.") if @ids.empty?
      return fail("Selecione no máximo #{MAX_ITEMS} anúncios para editar de uma vez.") if @ids.size > MAX_ITEMS

      items = @account.ml_items.where(item_id: @ids).index_by(&:item_id)
      missing = @ids - items.keys
      return fail("Anúncio não encontrado nesta conta: #{missing.join(', ')}.") if missing.any?

      rows = @ids.map { |id| row(items[id]) }
      skus = rows.first[:skus]
      if rows.size > 1
        return fail("Para editar vários anúncios juntos, todos precisam ter SKU. Sem SKU: #{rows.select { |r| r[:skus].empty? }.map { |r| r[:item_id] }.join(', ')}.") if rows.any? { |r| r[:skus].empty? }

        different = rows.reject { |r| r[:skus] == skus }
        if different.any?
          return fail("Só dá para editar juntos anúncios com o(s) mesmo(s) SKU(s). #{rows.first[:item_id]} tem #{skus.join(', ')}; " +
                      different.map { |r| "#{r[:item_id]} tem #{r[:skus].join(', ')}" }.join("; ") + ". Edite um de cada vez ou selecione só os do mesmo SKU.")
        end
      end

      Result.new(ok: true, message: nil, primary: rows.first, others: rows.drop(1), skus: skus)
    end

    private

    def row(item)
      skus = ([ item.sku ] + Array(item.inventory_refs).map { |r| r["sku"] }).map { |s| s.to_s.strip }.reject(&:blank?).uniq.sort
      { item_id: item.item_id, title: item.title, sku: item.sku, status: item.status, listing_type_id: item.listing_type_id,
        catalog_listing: !!item.catalog_listing, skus: skus }
    end

    def fail(message) = Result.new(ok: false, message: message, primary: nil, others: [], skus: [])
  end
end
