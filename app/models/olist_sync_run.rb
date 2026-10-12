# Rodada de sincronização dos produtos com o Olist: automática (a cada 3 min)
# ou pedida por um usuário.
class OlistSyncRun < ApplicationRecord
  TRIGGERS = %w[auto manual].freeze
  STATUSES = %w[running success failed].freeze
  # Rodada "running" sem terminar há tanto tempo: o worker caiu; deixa de bloquear novas.
  STALE_AFTER = 10.minutes
  STALE_ERROR = "A sincronização foi interrompida.".freeze

  belongs_to :company
  belongs_to :requested_by_user, class_name: "User", optional: true

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(started_at: :desc) }
  scope :active, -> { where(status: "running").where(started_at: STALE_AFTER.ago..) }

  def running? = status == "running"
end
