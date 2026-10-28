# Uma execução da rotina das 03:00 da seção Promoções (ver Painel::PromotionRoutine).
class MlPromotionRun < ApplicationRecord
  MODES = %w[simulation apply].freeze

  belongs_to :ml_account
  belongs_to :user, optional: true
  has_many :actions, class_name: "MlPromotionAction", foreign_key: :run_id, inverse_of: :run, dependent: :delete_all

  validates :mode, inclusion: { in: MODES }
end
