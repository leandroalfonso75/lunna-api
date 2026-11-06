# Linha do extrato de faturamento do Mercado Livre (cobranças e bonificações da conta), ligada à venda e ao envio
# quando o ML informa. Alimenta os custos do card Devoluções (frete de envio retido, frete de devolução, outros).
class MlBillingCharge < ApplicationRecord
  belongs_to :ml_account

  scope :charges, -> { where(detail_type: "CHARGE") }
  scope :bonuses, -> { where.not(detail_type: "CHARGE") }

  # valor com sinal: cobrança positiva, bonificação (devolução de valor ao vendedor) negativa
  def signed_amount = detail_type == "CHARGE" ? amount.to_f : -amount.to_f
end
