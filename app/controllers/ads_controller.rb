# GET /api/ads?account_id= → resumo, série diária e campanhas de Product Ads (últimos 3 meses).
# GET /api/ads/items?account_id= → anúncios em campanha, com filtros, ordenação e paginação.
# GET /api/ads/analysis?account_id= → análise e fila de decisões (regras em docs/secoes/ads.md).
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

  # Aba Análise: saúde da conta, famílias com sinais, leilão por campanha e a fila de decisões (só recomenda).
  def analysis
    render json: Painel::AdsAnalysis.call(Current.account, max_actions: params.fetch(:max_actions, Painel::AdsAnalysis::MAX_ACTIONS))
  end

  def sync
    Ml::AdsSyncJob.perform_later(Current.account.id)
    render json: { queued: true }, status: :accepted
  end
end
