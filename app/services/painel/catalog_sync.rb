# Anúncio tradicional sincronizado com anúncio de catálogo (a mesma regra de Promoções: item_relations de qualquer um dos
# dois lados). Usado na aba Anúncios › Tradicional (pedido do usuário em 25/11/2026) e na exclusão: excluir um tradicional
# sincronizado exclui também o anúncio de catálogo ligado a ele.
module Painel
  class CatalogSync
    def self.for(account) = new(account)

    def initialize(account)
      @account = account
    end

    # tradicional => [ids dos anúncios de catálogo sincronizados]
    def map
      @map ||= begin
        m = Hash.new { |h, k| h[k] = [] }
        @account.ml_items.where("jsonb_array_length(item_relations) > 0").pluck(:item_id, :catalog_listing, :item_relations).each do |id, catalog, rel|
          Array(rel).each do |r|
            other = r["id"].to_s.presence or next
            catalog ? m[other] << id : m[id] << other
          end
        end
        m.transform_values { |ids| ids.uniq.sort }
      end
    end

    def catalog_ids_for(traditional_id) = map.fetch(traditional_id, [])

    # [{ item_id:, permalink:, status: }] dos catálogos de um tradicional (link para o anúncio de catálogo)
    def links_for(traditional_id)
      catalog_ids_for(traditional_id).map do |id|
        info = catalog_info[id]
        { item_id: id, permalink: info&.dig(:permalink) || Painel::Labels.links(id)[:public], status: info&.dig(:status) }
      end
    end

    private

    def catalog_info
      @catalog_info ||= @account.ml_items.where(item_id: map.values.flatten.uniq)
                                .pluck(:item_id, :permalink, :status).to_h { |id, link, status| [ id, { permalink: link, status: status } ] }
    end
  end
end
