# Seção Reclamações (somente leitura do que foi importado do Mercado Livre; ver Painel::ClaimsQuery).
# GET /api/claims?account_id=&q=&page=&per_page= → lista, mais novas primeiro, com a venda ligada e o andamento da importação
# GET /api/claims/:id?account_id=               → uma reclamação com tudo o que o ML informou
# POST /api/claims/:id/reply?account_id=         → responde no ML (admin; receiver_role, message, confirm: true)
class ClaimsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :reply ]

  def index
    render json: Painel::ClaimsQuery.list(Current.account, params)
  end

  # Escrita no Mercado Livre: exige confirm=true em cada envio.
  def reply
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para responder no Mercado Livre." ], status: :unprocessable_content)
    end

    result = Painel::ClaimReply.call(Current.account, params[:id].to_i, receiver: params[:receiver_role], text: params[:message], user: Current.user)
    if result.ok
      render json: { ok: true, message: result.message, claim: Painel::ClaimsQuery.detail(Current.account, params[:id].to_i) }, status: :created
    else
      render json: { ok: false, errors: [ result.message ] }, status: result.reply ? :bad_gateway : :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Reclamação não encontrada." ], status: :not_found)
  end

  def show
    render json: Painel::ClaimsQuery.detail(Current.account, params[:id].to_i)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Reclamação não encontrada." ], status: :not_found)
  end
end
