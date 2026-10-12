# Conexão do Olist ERP da empresa e sincronização dos produtos (nada aparece no painel ainda).
#   GET    /api/olist           → estado da conexão (logado)
#   POST   /api/olist/authorize → {url} para o admin autorizar no Olist
#   DELETE /api/olist           → desconecta (admin)
#   POST   /api/olist/sync      → pede a atualização dos produtos agora (logado)
#   GET    /api/olist/sync_runs → últimas sincronizações (logado)
class OlistController < ApplicationController
  before_action :require_admin!, only: [ :authorize, :destroy ]

  def show
    render json: { olist: payload(Current.company.olist_connection) }
  end

  def authorize
    unless Olist::OAuth.configured?
      return render_errors([ "Integração com o Olist ERP não configurada (OLIST_CLIENT_ID e OLIST_CLIENT_SECRET)." ], status: :unprocessable_content)
    end

    OlistOauthState.expired.delete_all
    state = OlistOauthState.create!(state: SecureRandom.uuid, company: Current.company, user: Current.user)

    render json: { url: Olist::OAuth.authorize_url(state.state) }
  end

  def destroy
    Current.company.olist_connection&.destroy!
    head :no_content
  end

  # Atualização pedida pelo usuário. Se já houver uma em andamento (a automática
  # roda a cada 3 min), devolve a que está rodando em vez de abrir outra.
  def sync
    connection = Current.company.olist_connection
    if connection.nil? || connection.reauth_required?
      return render_errors([ "Olist ERP não conectado." ], status: :unprocessable_content)
    end

    run, created = Olist::SyncProducts.start_run(connection, trigger: "manual", user: Current.user)
    Olist::SyncJob.perform_later(connection.id, run.id) if created

    render json: { sync_run: run_payload(run), already_running: !created }, status: created ? :accepted : :ok
  end

  def sync_runs
    runs = Current.company.olist_sync_runs.recent.limit(20)
    render json: { sync_runs: runs.map { |run| run_payload(run) } }
  end

  private

  def payload(connection)
    return { configured: Olist::OAuth.configured?, connected: false } if connection.nil?

    {
      configured: Olist::OAuth.configured?,
      connected: connection.status == "active",
      status: connection.status,
      error: connection.last_error,
      connected_at: connection.created_at,
      connected_by: connection.connected_by_user&.name,
      access_expires_at: connection.expires_at,
      refresh_expires_at: connection.refresh_expires_at,
      products_count: Current.company.olist_products.count,
      last_sync: (run = Current.company.olist_sync_runs.recent.first) && run_payload(run)
    }
  end

  def run_payload(run)
    {
      id: run.id, trigger: run.trigger, status: run.status, products_count: run.products_count,
      error: run.error, started_at: run.started_at, finished_at: run.finished_at
    }
  end
end
