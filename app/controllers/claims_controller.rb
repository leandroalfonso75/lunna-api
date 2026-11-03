# Seção Reclamações (somente leitura do que foi importado do Mercado Livre; ver Painel::ClaimsQuery).
# GET /api/claims?account_id=&q=&page=&per_page= → lista, mais novas primeiro, com a venda ligada e o andamento da importação
# GET /api/claims/:id?account_id=               → uma reclamação com tudo o que o ML informou
class ClaimsController < ApplicationController
  include CurrentAccount

  def index
    render json: Painel::ClaimsQuery.list(Current.account, params)
  end

  def show
    render json: Painel::ClaimsQuery.detail(Current.account, params[:id].to_i)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Reclamação não encontrada." ], status: :not_found)
  end
end
