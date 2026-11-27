# Referência da redução de margem de um anúncio em Promoções (ver Painel::PromotionDropRef).
class MlPromotionDropRef < ApplicationRecord
  SOURCES = %w[inicial automacao manual].freeze

  belongs_to :ml_account
  belongs_to :user, optional: true

  validates :item_id, :margin_pct, :set_at, :key, presence: true
  validates :source, inclusion: { in: SOURCES }
end
