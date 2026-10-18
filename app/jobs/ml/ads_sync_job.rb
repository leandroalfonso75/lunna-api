# Seção Ads: baixa de novo as campanhas, anúncios e métricas de publicidade (pedido do usuário).
module Ml
  class AdsSyncJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      account = MlAccount.active.find_by(id: account_id)
      return unless account

      Ml::OAuth.refresh!(account)
      client = Ml::Client.new(access_token: account.access_token)
      Ml::Sync::Ads.call(client, account)
      # pedido do usuário: baixa de uma vez todos os dias que faltam do gasto por anúncio
      Ml::Sync::Ads.backfill_item_days(client, account)
    rescue Ml::OAuth::Error => e
      Rails.logger.warn("Ml::AdsSyncJob: #{e.message}")
    end
  end
end
