# Uma ação do Lunna numa promoção do Mercado Livre (ver Painel::PromotionActions).
class MlPromotionAction < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true
  belongs_to :run, class_name: "MlPromotionRun", optional: true, inverse_of: :actions
end
