# Seção Estoque (pedido do usuário em 14/11/2026). Somente leitura.
# GET /api/stock/depot?account_id=&q=&view=&sort=&page=  → estoque do depósito (Olist) por SKU, com Full, cobertura e valor
# GET /api/stock/full?account_id=&q=&view=&page=         → estoque Full e recomendações de reposição do ML
# POST /api/stock/full/sync?account_id=                  → relê as recomendações do Full agora (admin)
class StockController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :sync_full ]

  def depot
    render json: Painel::StockQuery.depot(Current.account, params)
  end

  def full
    render json: Painel::StockQuery.full(Current.account, params)
  end

  def sync_full
    Ml::FullReplenishmentJob.perform_later(Current.account.id)
    render json: { queued: true }, status: :accepted
  end
end
