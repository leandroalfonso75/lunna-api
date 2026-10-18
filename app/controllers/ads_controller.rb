# GET /api/ads?account_id= → resumo, série diária e campanhas de Product Ads (últimos 3 meses).
# GET /api/ads/items?account_id= → anúncios em campanha, com filtros, ordenação e paginação.
# POST /api/ads/sync?account_id= (admin) → lê de novo as campanhas e métricas do Mercado Livre.
class AdsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :sync ]

  def index
    render json: Painel::AdsQuery.call(Current.account, params)
  end

  def items
    render json: Painel::AdsQuery.items(Current.account, params)
  end

  def sync
    Ml::AdsSyncJob.perform_later(Current.account.id)
    render json: { queued: true }, status: :accepted
  end
end
