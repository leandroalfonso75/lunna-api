# GET /api/items (SPEC 10.4) → tabela de anúncios com filtros, busca,
# ordenação e paginação, tudo resolvido no Ruby (Painel::ItemQuery).
class ItemsController < ApplicationController
  include CurrentAccount

  def index
    render json: Painel::ItemQuery.call(Current.account, params)
  end
end
