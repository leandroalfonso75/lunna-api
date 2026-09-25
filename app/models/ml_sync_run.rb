# Log de uma rodada de sincronização (SPEC 4/5, DECISOES §6).
class MlSyncRun < ApplicationRecord
  belongs_to :ml_account

  scope :unfinished, -> { where(finished_at: nil) }
end
