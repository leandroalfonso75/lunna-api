# Sincroniza os produtos de uma empresa com o Olist. Recebe o id de uma rodada
# já criada (pedido manual) ou, no modo automático, cria uma — e se já houver
# outra em andamento, não faz nada (quem criou a rodada é quem a executa).
module Olist
  class SyncJob < ApplicationJob
    def perform(connection_id, run_id = nil)
      connection = OlistConnection.find_by(id: connection_id)
      return if connection.nil? || connection.reauth_required?

      run = run_id ? OlistSyncRun.find_by(id: run_id) : start_automatic_run(connection)
      return if run.nil? || !run.running?

      Olist::SyncProducts.new(connection, run).call
      Olist::SyncCostsJob.perform_later(connection.id) if run.reload.status == "success"
    end

    private

    def start_automatic_run(connection)
      run, created = Olist::SyncProducts.start_run(connection, trigger: "auto")
      created ? run : nil
    end
  end
end
