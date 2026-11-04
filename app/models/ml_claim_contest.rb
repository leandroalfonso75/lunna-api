# Andamento da contestação de uma reclamação que afeta a reputação (ver Painel::ClaimContest).
class MlClaimContest < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true

  validates :status, inclusion: { in: Painel::ClaimContest::STATUSES }
end
