# Consulta feita no Radar Mercado Livre (botão "Pesquisar"): guarda os filtros e o
# resumo do resultado para o usuário reabrir depois. Fica disponível por 3 meses.
class RadarSearch < ApplicationRecord
  RETENTION = 3.months
  MAX_FILTERS_BYTES = 4.kilobytes

  belongs_to :company
  belongs_to :user, optional: true

  normalizes :category_path, with: ->(value) { value.to_s.split(">").map(&:strip).join(" > ") }

  validates :category_path, presence: true, length: { maximum: 500 }
  validates :total_items, :total_sold, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :total_revenue, :median_price, numericality: { greater_than_or_equal_to: 0 }
  validate :filters_are_small_hash

  # Consultas dos últimos 3 meses, da mais nova para a mais antiga.
  scope :recent, -> { where(created_at: RETENTION.ago..).order(created_at: :desc) }

  private

  def filters_are_small_hash
    return errors.add(:filters, "deve ser um objeto") unless filters.is_a?(Hash)

    errors.add(:filters, "é grande demais") if filters.to_json.bytesize > MAX_FILTERS_BYTES
  end
end
