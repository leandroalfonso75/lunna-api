# Conversa de pós-venda do Mercado Livre com um comprador (seção Mensagens). As mensagens ficam em `messages` (jsonb),
# da mais antiga para a mais nova.
class MlConversation < ApplicationRecord
  STATUS_LABELS = { "active" => "Aberta", "blocked" => "Bloqueada pelo ML" }.freeze
  SUBSTATUS_LABELS = {
    "blocked_by_cancelled_order" => "pedido cancelado", "blocked_by_time" => "prazo para mensagens encerrado",
    "blocked_by_mediation" => "há uma reclamação aberta", "blocked_by_buyer" => "bloqueada pelo comprador",
    "blocked_by_fulfillment" => "pedido Full", "blocked_by_payment" => "pagamento pendente"
  }.freeze

  belongs_to :ml_account

  def can_send? = status == "active"
  def awaiting_seller? = last_from == "buyer"
end
