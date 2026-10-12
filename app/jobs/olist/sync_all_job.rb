# Agendado a cada 3 minutos (config/recurring.yml): enfileira uma sincronização
# de produtos por empresa com o Olist conectado. Quem pede a atualização na hora
# usa POST /api/olist/sync.
module Olist
  class SyncAllJob < ApplicationJob
    def perform
      OlistConnection.active.find_each { |connection| Olist::SyncJob.perform_later(connection.id) }
    end
  end
end
