# GET /api/ml_accounts (logado) → {ml_accounts}
# POST /api/ml_accounts/authorize (admin) → 200 {url}
# POST /api/ml_accounts/connect (admin) → termina o OAuth a partir do
#   {code, state} que o front recebeu do GET /auth/ml/callback (DECISOES §5)
# DELETE /api/ml_accounts/:id (admin) → 204 (apaga a conta; FKs cascateiam os dados)
class MlAccountsController < ApplicationController
  before_action :require_admin!, only: [ :authorize, :connect, :destroy ]

  def index
    render json: { ml_accounts: Current.company.ml_accounts.order(:created_at).map { |account| ml_account_payload(account) } }
  end

  def authorize
    unless Ml::OAuth.configured?
      return render_errors([ "Integração com o Mercado Livre não configurada." ], status: :unprocessable_content)
    end

    MlOauthState.expired.delete_all
    state = MlOauthState.create!(state: SecureRandom.uuid, company: Current.company, user: Current.user)

    render json: { url: Ml::OAuth.authorize_url(state.state) }
  end

  # O state só é aceito pelo mesmo usuário/empresa que o gerou (DECISOES §5)
  # — impede que outra pessoa "queime" o state de alguém, mesmo dentro da
  # mesma empresa.
  def connect
    outcome = consume_state(params[:state])

    case outcome[:result]
    when :invalid
      return oauth_error("expirada", "Autorização expirada. Tente conectar de novo.", status: :unprocessable_content)
    when :forbidden
      return oauth_error("sem_permissao", "Essa autorização foi iniciada por outro usuário. Gere um novo link de conexão.", status: :forbidden)
    end

    finish_connection(company_id: outcome[:company_id], user_id: outcome[:user_id])
  rescue => e
    Rails.logger.error("Ml::OAuth connect: erro inesperado (#{e.class})")
    oauth_error("erro", "Não foi possível concluir a conexão com o Mercado Livre. Tente novamente.", status: :unprocessable_content)
  end

  def destroy
    Current.company.ml_accounts.find(params[:id]).destroy!
    head :no_content
  end

  private

  def finish_connection(company_id:, user_id:)
    unless Ml::OAuth.configured?
      return oauth_error("erro_config", "Integração com o Mercado Livre não configurada.", status: :unprocessable_content)
    end

    begin
      data = Ml::OAuth.exchange_code(params[:code])
    rescue Ml::OAuth::Error => e
      Rails.logger.error("Ml::OAuth connect: falha ao trocar code (#{e.class})")
      return oauth_error("erro", "Não foi possível concluir a conexão com o Mercado Livre. Tente novamente.", status: :unprocessable_content)
    end

    if data["refresh_token"].blank?
      return oauth_error("sem_offline_access",
        "O aplicativo precisa da permissão offline_access no Mercado Livre. Autorize de novo.",
        status: :unprocessable_content)
    end

    me = Ml::Client.new(access_token: data["access_token"]).me
    seller_id = data["user_id"] || me["id"]

    account = MlAccount.find_or_initialize_by(seller_id: seller_id)
    if account.persisted? && account.company_id != company_id
      return oauth_error("outra_empresa", "Essa conta do Mercado Livre já está conectada a outra empresa.", status: :conflict)
    end

    account.assign_attributes(
      company_id: company_id,
      nickname: me["nickname"],
      access_token: data["access_token"],
      refresh_token: data["refresh_token"],
      expires_at: Time.current + (data["expires_in"] || 21_600),
      scope: data["scope"],
      status: "active",
      last_error: nil,
      connected_by_user_id: user_id
    )
    account.save!

    Ml::SyncJob.perform_later(account.id)

    render json: { code: "conectada", ml_account: ml_account_payload(account) }
  end

  # Busca com lock e, se o state existir, não estiver expirado e for do
  # mesmo usuário/empresa autenticados, consome (apaga) na hora — uso único.
  # Em qualquer outro caso o state é preservado (o expirado por hygiene já é
  # limpo em `authorize`; o de outro usuário/empresa fica intacto de
  # propósito, pra não deixar um terceiro queimar o state de outra pessoa).
  def consume_state(token)
    MlOauthState.transaction do
      state = MlOauthState.lock.find_by(state: token)
      next { result: :invalid } if state.nil? || state.created_at < MlOauthState::TTL.ago
      next { result: :forbidden } if state.user_id != Current.user.id || state.company_id != Current.company.id

      company_id = state.company_id
      user_id = state.user_id
      state.destroy!

      { result: :ok, company_id: company_id, user_id: user_id }
    end
  end

  def oauth_error(code, message, status:)
    render json: { errors: [ message ], code: code }, status: status
  end
end
