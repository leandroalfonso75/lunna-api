# GET /api/ads?account_id= → resumo, série diária e campanhas de Product Ads (últimos 3 meses).
# GET /api/ads/items?account_id= → anúncios em campanha, com filtros, ordenação e paginação.
# GET /api/ads/analysis?account_id= → análise e fila de decisões (regras em docs/secoes/ads.md).
# POST /api/ads/sync?account_id= (admin) → lê de novo as campanhas e métricas do Mercado Livre.
class AdsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :sync, :decide, :undecide ]

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

  # Diagnóstico de uma família (?family=) ou campanha (?campaign_id=): veredito, evidência, descartados, o que fazer.
  def diagnosis
    result = Painel::AdsDiagnosis.call(Current.account, family: params[:family], campaign_id: params[:campaign_id])
    return render_errors([ "Família ou campanha não encontrada." ], status: :not_found) unless result

    render json: result
  end

  # Marca um item da fila como feito ou ignorado (guarda o "antes"); a análise mostra o "depois" 7 dias depois.
  def decide
    decision = Painel::AdsAnalysis.decide(Current.account, params.permit(:key, :signal, :status).to_h.symbolize_keys, user: Current.user)
    return render_errors([ "Item da fila não encontrado." ], status: :not_found) unless decision

    render json: Painel::AdsAnalysis.decision_payload(decision), status: :created
  end

  def undecide
    Current.account.ml_ad_decisions.find(params[:id]).destroy!
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Decisão não encontrada." ], status: :not_found)
  end

  def sync
    Ml::AdsSyncJob.perform_later(Current.account.id)
    render json: { queued: true }, status: :accepted
  end
end
