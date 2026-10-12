# Registro de auditoria de uma alteração feita no Olist ERP pelo Lunna.
# Gravado ANTES de chamar o Olist (pending) e fechado como done/failed.
class OlistChange < ApplicationRecord
  KINDS = %w[price stock].freeze
  STATUSES = %w[pending done failed].freeze

  belongs_to :company
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :olist_product_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
