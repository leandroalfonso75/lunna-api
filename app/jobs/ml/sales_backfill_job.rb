# Seção Vendas: baixa os pedidos dos últimos 3 meses e os detalhes de envio de cada um.
# Pedido do usuário (botão "Atualizar vendas"); a sincronização normal (5 min) completa o que
# sobrar, 60 envios por rodada. Roda em pedaços e se reagenda enquanto houver envios a ler.
module Ml
  class SalesBackfillJob < ApplicationJob
    queue_as :default

    DAYS = 92
    CHUNK = 100
    MAX_CHUNKS_PER_RUN = 15

    def perform(account_id, orders_done: false)
      account = MlAccount.active.find_by(id: account_id)
      return unless account

      Ml::OAuth.refresh!(account)
      client = Ml::Client.new(access_token: account.access_token)
      since = DAYS.days.ago.beginning_of_day

      Ml::Sync::Orders.call(client, account, from: since) unless orders_done

      MAX_CHUNKS_PER_RUN.times do
        result = Ml::Sync::Shipments.call(client, account, limit: CHUNK, since: since)
        return if result.remaining.zero? || result.count.zero?
      end

      self.class.perform_later(account.id, orders_done: true)
    rescue Ml::OAuth::Error => e
      Rails.logger.warn("Ml::SalesBackfillJob: #{e.message}")
    end
  end
end
