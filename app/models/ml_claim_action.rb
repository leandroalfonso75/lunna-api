# Ação de resolução feita pelo Lunna numa reclamação do ML (ver Painel::ClaimAction).
class MlClaimAction < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true

  validates :action, inclusion: { in: %w[allow_return refund partial_refund open_dispute] }
end
