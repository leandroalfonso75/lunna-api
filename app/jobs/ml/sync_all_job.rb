# Agendado a cada 5 min (config/recurring.yml): enfileira uma sincronização por conta ativa.
# Conta reauth_required: desde 28/11/2026 tenta renovar sozinha algumas vezes (Ml::OAuth.auto_retry!); se voltar a valer,
# sincroniza na hora. Depois das tentativas, fica parada até nova autorização.
module Ml
  class SyncAllJob < ApplicationJob
    def perform
      MlAccount.where(status: "reauth_required").find_each do |account|
        Ml::SyncJob.perform_later(account.id) if Ml::OAuth.auto_retry!(account)
      rescue StandardError => e
        Rails.logger.error("Ml::SyncAllJob auto_retry #{account.id}: #{e.class}: #{e.message}")
      end
      MlAccount.active.find_each { |account| Ml::SyncJob.perform_later(account.id) }
    end
  end
end
