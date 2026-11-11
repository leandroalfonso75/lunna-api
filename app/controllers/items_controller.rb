# GET /api/items (SPEC 10.4) → tabela de anúncios com filtros, busca,
# ordenação e paginação, tudo resolvido no Ruby (Painel::ItemQuery).
class ItemsController < ApplicationController
  include CurrentAccount

  def index
    render json: Painel::ItemQuery.call(Current.account, params)
  end

  # GET /api/items/catalog → aba Catálogo: anúncios de catálogo, sincronização com tradicional e ganhando/perdendo
  def catalog
    render json: Painel::CatalogQuery.call(Current.account, params)
  end
end
