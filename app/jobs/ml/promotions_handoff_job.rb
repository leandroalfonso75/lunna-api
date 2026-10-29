# Seção Promoções: quando a nova promoção de um anúncio começa (ver PromotionActions "agendar"), sai da anterior,
# que ainda estava valendo.
module Ml
  class PromotionsHandoffJob < ApplicationJob
    queue_as :default

    def perform(account_id, item_id, from_target, to_target, source = "rotina")
      account = MlAccount.active.find_by(id: account_id)
      return unless account

      Painel::PromotionActions.new(account, nil, source).handoff(item_id, from_target.symbolize_keys, to_target.symbolize_keys)
    end
  end
end
