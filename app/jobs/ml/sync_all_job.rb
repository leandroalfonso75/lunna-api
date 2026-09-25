# Agendado a cada 5 min (config/recurring.yml): enfileira uma sincronização
# por conta ativa. Contas reauth_required ficam paradas até nova autorização.
module Ml
  class SyncAllJob < ApplicationJob
    def perform
      MlAccount.active.find_each { |account| Ml::SyncJob.perform_later(account.id) }
    end
  end
end
