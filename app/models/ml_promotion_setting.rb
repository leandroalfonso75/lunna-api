# Margem mínima/máxima de promoção de um anúncio (sem valor = vale a regra geral da empresa).
class MlPromotionSetting < ApplicationRecord
  belongs_to :ml_account
  belongs_to :updated_by, class_name: "User", optional: true

  validates :min_margin_pct, :max_margin_pct, numericality: { greater_than: -100, less_than: 100 }, allow_nil: true
  validates :min_price, :max_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :limit_mode, inclusion: { in: %w[margin price] }
  validate :max_above_min
  validate :max_price_above_min_price

  private

  def max_above_min
    return if min_margin_pct.nil? || max_margin_pct.nil? || max_margin_pct >= min_margin_pct

    errors.add(:max_margin_pct, "precisa ser maior ou igual à margem mínima")
  end

  def max_price_above_min_price
    return if min_price.nil? || max_price.nil? || max_price >= min_price

    errors.add(:max_price, "precisa ser maior ou igual ao valor mínimo")
  end
end
