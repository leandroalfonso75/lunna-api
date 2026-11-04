# Seção Reclamações (somente leitura do que foi importado do Mercado Livre; ver Painel::ClaimsQuery).
# GET /api/claims?account_id=&q=&page=&per_page= → lista, mais novas primeiro, com a venda ligada e o andamento da importação
# GET /api/claims/:id?account_id=               → uma reclamação com tudo o que o ML informou
# POST /api/claims/:id/reply?account_id=         → responde no ML (admin; receiver_role, message, confirm: true)
class ClaimsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :reply, :contest ]

  # Assistente de contestação: as que afetam a reputação, no prazo de 60 dias, com grupo, provas e texto sugerido.
  def contests
    render json: Painel::ClaimContest.list(Current.account)
  end

  # Andamento da contestação (feita pelo vendedor no ML): status e o texto usado. Não envia nada ao ML.
  def contest
    claim = Current.account.ml_claims.find_by!(claim_id: params[:id].to_i)
    record = Current.account.ml_claim_contests.find_or_initialize_by(claim_id: claim.claim_id)
    record.assign_attributes(status: params[:status].presence || record.status, user: Current.user)
    record.text = params[:text] if params.key?(:text)
    record.contested_at ||= Time.current if record.status == "contestada"
    if record.save
      render json: { claim_id: claim.claim_id, status: record.status, contested_at: record.contested_at }
    else
      render_errors(record.errors.full_messages, status: :unprocessable_content)
    end
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Reclamação não encontrada." ], status: :not_found)
  end

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
