# Uma rodada por vez por conta (DECISOES §6): `limits_concurrency` descarta
# qualquer execução concorrente pra mesma conta (o próprio Ml::Sync::Run
# também sabe recusar rodada duplicada, pro caso de reinício do worker).
module Ml
  class SyncJob < ApplicationJob
    limits_concurrency to: 1, key: ->(account_id, *) { account_id }, duration: 20.minutes, on_conflict: :discard

    def perform(account_id, run_id = nil)
      account = MlAccount.find_by(id: account_id)
      return unless account

      Ml::Sync::Run.call(account, run_id: run_id)
    end
  end
end
