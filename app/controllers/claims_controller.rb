# Seção Reclamações (somente leitura do que foi importado do Mercado Livre; ver Painel::ClaimsQuery).
# GET /api/claims?account_id=&q=&page=&per_page= → lista, mais novas primeiro, com a venda ligada e o andamento da importação
# GET /api/claims/:id?account_id=               → uma reclamação com tudo o que o ML informou
# POST /api/claims/:id/reply?account_id=         → responde no ML (admin; receiver_role, message, confirm: true)
class ClaimsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :reply, :contest, :resolve, :partial_refund_offers, :return_cost ]

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

  # Resolver pelo Lunna (escrita no ML, não se desfaz): action = allow_return | refund | partial_refund | open_dispute,
  # percentage (reembolso parcial) e confirm=true.
  def resolve
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para agir na reclamação no Mercado Livre." ], status: :unprocessable_content)
    end

    result = Painel::ClaimAction.call(Current.account, params[:id].to_i, action: params[:action_name], user: Current.user, percentage: params[:percentage])
    if result.ok
      render json: { ok: true, message: result.message, claim: Painel::ClaimsQuery.detail(Current.account, params[:id].to_i) }, status: :created
    else
      render json: { ok: false, errors: [ result.message ] }, status: result.record ? :bad_gateway : :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Reclamação não encontrada." ], status: :not_found)
  end

  def partial_refund_offers
    claim = Current.account.ml_claims.find_by!(claim_id: params[:id].to_i)
    render json: Painel::ClaimAction.partial_offers(Current.account, claim.claim_id)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Reclamação não encontrada." ], status: :not_found)
  rescue Ml::Client::Error => e
    render_errors([ "O Mercado Livre não informou os valores de reembolso parcial: #{e.message.truncate(120)}" ], status: :unprocessable_content)
  end

  # Antes de "Oferecer devolução": quanto o frete da devolução custa ao vendedor (aviso, como no ML). Só leitura.
  def return_cost
    claim = Current.account.ml_claims.find_by!(claim_id: params[:id].to_i)
    Ml::OAuth.refresh!(Current.account)
    data = Ml::Client.new(access_token: Current.account.reload.access_token).claim_return_cost(claim.claim_id)
    amount = data["amount"].to_f
    render json: { amount: amount, currency_id: data["currency_id"], free: amount.zero? }
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Reclamação não encontrada." ], status: :not_found)
  rescue Ml::Client::Error, Ml::OAuth::Error
    render_errors([ "O Mercado Livre não informou o custo do frete de devolução agora." ], status: :unprocessable_content)
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
