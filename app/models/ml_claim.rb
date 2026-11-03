# Reclamação do Mercado Livre (seção Reclamações): cancelamento, mediação ou devolução, com tudo o que a API informa
# (ver Ml::Sync::ClaimsCenter e docs/secoes/reclamacoes.md).
class MlClaim < ApplicationRecord
  belongs_to :ml_account

  scope :open_claims, -> { where(status: "opened") }

  def order
    order_id && MlOrder.find_by(order_id: order_id, ml_account_id: ml_account_id)
  end
end
