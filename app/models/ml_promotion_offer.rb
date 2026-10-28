# Oferta de promoção de um anúncio (candidato, ativa ou pendente), lida de /seller-promotions/items/{id}.
class MlPromotionOffer < ApplicationRecord
  belongs_to :ml_account

  # Preço livre dentro de uma faixa (o vendedor escolhe); as demais têm preço fixo dado pelo ML.
  FLEXIBLE_TYPES = %w[SELLER_CAMPAIGN DEAL PRICE_DISCOUNT LIGHTNING].freeze
  ACTIVE_STATUSES = %w[started pending].freeze

  def flexible? = FLEXIBLE_TYPES.include?(promotion_type) && max_price.to_f.positive?

  # Relâmpago e oferta do dia reservam estoque: o ML sugere o mínimo (stock.min) que o anúncio precisa separar.
  STOCK_TYPES = %w[LIGHTNING SMART_LIGHTNING DOD].freeze

  def stock_reserved
    return nil unless STOCK_TYPES.include?(promotion_type)

    (payload || {}).dig("stock", "min")&.to_i
  end
  def active? = ACTIVE_STATUSES.include?(status)
end
