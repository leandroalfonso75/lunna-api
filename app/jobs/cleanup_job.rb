# Agendado diariamente (config/recurring.yml): limpa states de OAuth
# expirados, sessões vencidas e o histórico antigo de rodadas de sync.
class CleanupJob < ApplicationJob
  SYNC_RUNS_MAX_AGE = 30.days

  def perform
    MlOauthState.expired.delete_all
    OlistOauthState.expired.delete_all
    Session.where("expires_at <= ?", Time.current).delete_all
    OlistSyncRun.where("started_at <= ?", SYNC_RUNS_MAX_AGE.ago).delete_all
    MlSyncRun.where("started_at <= ?", SYNC_RUNS_MAX_AGE.ago).delete_all
  end
end
