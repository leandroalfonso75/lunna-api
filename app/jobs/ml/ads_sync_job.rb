# Seção Ads: baixa de novo as campanhas, anúncios e métricas de publicidade (pedido do usuário).
module Ml
  class AdsSyncJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      account = MlAccount.active.find_by(id: account_id)
      return unless account

      Ml::OAuth.refresh!(account)
      Ml::Sync::Ads.call(Ml::Client.new(access_token: account.access_token), account)
    rescue Ml::OAuth::Error => e
      Rails.logger.warn("Ml::AdsSyncJob: #{e.message}")
    end
  end
end
