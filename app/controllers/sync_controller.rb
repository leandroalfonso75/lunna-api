# POST /api/sync?account_id= (admin) → dispara uma sincronização manual
# GET /api/sync/runs?account_id=&limit=20 (logado) → histórico de rodadas
class SyncController < ApplicationController
  before_action :require_admin!, only: [ :create ]

  def create
    account = Current.company.ml_accounts.find(params[:account_id])

    if account.ml_sync_runs.unfinished.where("started_at > ?", Ml::Sync::Run::STALE_AFTER.ago).exists?
      return render_errors([ "Já existe uma sincronização em andamento para esta conta." ], status: :conflict)
    end

    run = account.ml_sync_runs.create!(started_at: Time.current)
    Ml::SyncJob.perform_later(account.id, run.id)

    render json: { run_id: run.id }, status: :accepted
  end

  def runs
    account = Current.company.ml_accounts.find(params[:account_id])
    runs = account.ml_sync_runs.order(started_at: :desc).limit(runs_limit)

    render json: { runs: runs.map { |run| sync_run_payload(run) } }
  end

  private

  def runs_limit
    limit = params[:limit].presence&.to_i || 20
    limit = 20 if limit <= 0
    [ limit, 100 ].min
  end
end
