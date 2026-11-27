# Atualização automática das fichas vindas do ERP (27/11/2026): o ERP manda nos dados, então o que mudar lá chega ao
# Lunna. A cada rodada (Erp::CatalogRefreshJob), para cada empresa que já migrou os produtos:
# - reimporta as fichas cujo produto (ou alguma variação) foi alterado no ERP depois da última importação;
# - importa os produtos ativos novos no ERP que ainda não têm ficha.
# Poucos por rodada (o ERP limita as chamadas); o resto fica para a próxima. Inativos/excluídos e removidos da lista do
# Lunna continuam fora (Erp::CatalogImport). Só leitura no ERP.
module Erp
  module CatalogRefresh
    PER_RUN = 15

    module_function

    # => ids do ERP enviados para (re)importar
    def call(company, per_run: PER_RUN, importer: CatalogImport)
      return [] unless company.olist_connection&.status == "active"

      fichas = company.catalog_products.where(source: "erp").pluck(:erp_id, :erp_synced_at).to_h
      return [] if fichas.empty? # só para quem já migrou

      tops = company.olist_products.where(parent_olist_id: nil, status: "A", hidden_at: nil).pluck(:olist_id, :olist_updated_at).to_h
      children = company.olist_products.where(parent_olist_id: tops.keys).group(:parent_olist_id).maximum(:olist_updated_at)
      changed = tops.filter_map do |id, updated|
        synced = fichas[id]
        last = [ updated, children[id] ].compact.max
        id if synced.nil? || (last && last > synced)
      end
      ids = changed.first(per_run)
      importer.call(company, erp_ids: ids) if ids.any?
      ids
    end
  end
end
