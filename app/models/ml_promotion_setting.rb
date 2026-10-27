# Margem mínima/máxima de promoção de um anúncio (sem valor = vale a regra geral da empresa).
class MlPromotionSetting < ApplicationRecord
  belongs_to :ml_account
  belongs_to :updated_by, class_name: "User", optional: true

  validates :min_margin_pct, :max_margin_pct, numericality: { greater_than: -100, less_than: 100 }, allow_nil: true
  validate :max_above_min

  private

  def max_above_min
    return if min_margin_pct.nil? || max_margin_pct.nil? || max_margin_pct >= min_margin_pct

    errors.add(:max_margin_pct, "precisa ser maior ou igual à margem mínima")
  end
end
