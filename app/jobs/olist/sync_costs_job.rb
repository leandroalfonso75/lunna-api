# Calcula o custo PEPS dos produtos de uma empresa (em lotes). Só um por empresa
# por vez; é enfileirado ao fim de cada sincronização de produtos.
module Olist
  class SyncCostsJob < ApplicationJob
    limits_concurrency to: 1, key: ->(connection_id) { connection_id }

    def perform(connection_id)
      connection = OlistConnection.find_by(id: connection_id)
      return if connection.nil? || connection.reauth_required?

      Olist::SyncCosts.new(connection).call
    end
  end
end
