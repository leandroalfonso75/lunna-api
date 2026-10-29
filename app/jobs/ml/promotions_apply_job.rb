# Seção Promoções: aplica a melhor oferta em vários anúncios, um de cada vez (pedido do usuário na tela).
# Cada anúncio fica no histórico (ml_promotion_actions) com o resultado.
module Ml
  class PromotionsApplyJob < ApplicationJob
    queue_as :default

    # target: nil = a melhor oferta de cada anúncio; { "promotion_id", "promotion_type" } = a mesma promoção em todos.
    def perform(account_id, item_ids, user_id = nil, target = nil)
      account = MlAccount.active.find_by(id: account_id)
      return unless account

      user = User.find_by(id: user_id)
      Array(item_ids).each do |item_id|
        result = Painel::PromotionActions.apply(account, item_id, user: user, source: "lote", target: target&.symbolize_keys)
        item = account.ml_items.find_by(item_id: item_id)
        Painel::CatalogCheck.schedule(account, item, result.action) if result.ok && result.action && item&.catalog_listing
      rescue ActiveRecord::RecordNotFound
        next
      end
    end
  end
end
