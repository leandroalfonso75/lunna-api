# Seção Promoções: aplica a melhor oferta em vários anúncios, um de cada vez (pedido do usuário na tela).
# Cada anúncio fica no histórico (ml_promotion_actions) com o resultado.
module Ml
  class PromotionsApplyJob < ApplicationJob
    queue_as :default

    def perform(account_id, item_ids, user_id = nil)
      account = MlAccount.active.find_by(id: account_id)
      return unless account

      user = User.find_by(id: user_id)
      Array(item_ids).each do |item_id|
        Painel::PromotionActions.apply(account, item_id, user: user, source: "lote")
      rescue ActiveRecord::RecordNotFound
        next
      end
    end
  end
end
