# GET /api/sales?account_id= → vendas (pedidos) do Mercado Livre com filtros, totais e série diária.
# GET /api/sales/:id?account_id=&period= (ou from/to) → um pedido com tudo o que a API entrega (pagamentos, itens, envio).
# POST /api/sales/sync?account_id= (admin) → baixa de novo os últimos 3 meses (pedidos + envios).
class SalesController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :sync ]

  def index
    render json: Painel::SalesQuery.call(Current.account, params)
  end

  def show
    render json: Painel::SalesQuery.detail(Current.account, params[:id], params)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Venda não encontrada." ], status: :not_found)
  end

  def sync
    Ml::SalesBackfillJob.perform_later(Current.account.id)
    render json: { queued: true }, status: :accepted
  end
end
