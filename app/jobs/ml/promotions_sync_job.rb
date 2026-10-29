# Seção Promoções: lê de novo a Central de Promoções do Mercado Livre (pedido do usuário, ou um anúncio só).
module Ml
  class PromotionsSyncJob < ApplicationJob
    queue_as :default

    def perform(account_id, item_ids = nil)
      account = MlAccount.active.find_by(id: account_id)
      return unless account

      Ml::OAuth.refresh!(account)
      client = Ml::Client.new(access_token: account.access_token)
      Ml::Sync::Promotions.call(client, account, item_ids: item_ids)
      Ml::Sync::CatalogStatus.call(client, account, item_ids: item_ids)
    rescue Ml::OAuth::Error => e
      Rails.logger.warn("Ml::PromotionsSyncJob: #{e.message}")
    end
  end
end
