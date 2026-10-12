# Conexão do Olist ERP (antigo Tiny) de uma empresa. Os tokens ficam cifrados.
# Somente leitura por ora: nenhuma escrita no ERP.
class OlistConnection < ApplicationRecord
  STATUSES = %w[active reauth_required].freeze

  belongs_to :company
  belongs_to :connected_by_user, class_name: "User", optional: true

  encrypts :access_token, :refresh_token

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  # Refresh token vencido (ou conexão que falhou ao renovar): só reconectando.
  def reauth_required? = status == "reauth_required"
end
