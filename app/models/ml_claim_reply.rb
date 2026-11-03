# Resposta enviada pelo Lunna numa reclamação do Mercado Livre (ver Painel::ClaimReply).
class MlClaimReply < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze
  RECEIVERS = %w[complainant mediator].freeze

  belongs_to :ml_account
  belongs_to :user, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :receiver_role, inclusion: { in: RECEIVERS }
  validates :message, presence: true
end
