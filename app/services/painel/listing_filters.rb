# Filtros da página Anúncios que ficam acima das abas Todos e Catálogo e se somam (cumulativos): "Anúncios criados há
# mais de" (Painel::CreatedFilter, 24/11/2026) e "Quantidade de Vendas" (Painel::SalesFilter, 25/11/2026). Ambos olham
# ml_items; valem também para as contagens das abas.
module Painel
  module ListingFilters
    def self.active?(params) = !!(CreatedFilter.days(params) || SalesFilter.value(params))

    # scope de ml_items com os filtros aplicados
    def self.apply(scope, params) = SalesFilter.apply(CreatedFilter.apply(scope, params), params)

    # ids dos anúncios que passam nos filtros (subquery), ou nil sem filtro
    def self.item_ids(account, params) = active?(params) ? apply(account.ml_items, params).select(:item_id) : nil
  end
end
