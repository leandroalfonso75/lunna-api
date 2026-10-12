# Pedido de coleta do Radar Mercado Livre para uma categoria (e subcategorias).
# Só nasce de um pedido explícito do usuário (nunca agendado). A fila registra o
# pedido; quem coleta e muda o status é o coletor, executado sob comando do dono.
class RadarCollection < ApplicationRecord
  STATUSES = %w[requested collecting done failed].freeze
  ACTIVE = %w[requested collecting].freeze
  PATH_SEPARATOR = " > ".freeze
  MAX_PATH_LENGTH = 500

  belongs_to :company
  belongs_to :requested_by_user, class_name: "User", optional: true

  normalizes :category_path, with: ->(value) { value.to_s.split(">").map(&:strip).join(PATH_SEPARATOR) }

  validates :category_path, presence: true, length: { maximum: MAX_PATH_LENGTH }
  validates :status, inclusion: { in: STATUSES }
  validate :no_other_active_request, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def active? = ACTIVE.include?(status)

  # Só dá para cancelar o que ainda não começou a coletar.
  def cancellable? = status == "requested"

  private

  def no_other_active_request
    return if company_id.blank? || category_path.blank?
    return unless RadarCollection.where(company_id: company_id, category_path: category_path, status: ACTIVE).exists?

    errors.add(:base, "Já existe um pedido de coleta em aberto para essa categoria.")
  end
end
