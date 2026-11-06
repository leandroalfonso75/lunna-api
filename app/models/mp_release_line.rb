# Movimento da conta do Mercado Pago, do relatório de liberações: crédito ou débito, o motivo (description) e o saldo.
class MpReleaseLine < ApplicationRecord
  belongs_to :ml_account

  # rótulos dos movimentos que aparecem no relatório (description)
  LABELS = {
    "payment" => "Liberação de vendas", "shipping" => "Fretes pagos pelos compradores", "refund" => "Reembolsos",
    "mediation" => "Mediações", "reserve_for_dispute" => "Reservas por reclamação", "reserve_for_debt_payment" => "Reserva para pagar dívida com o ML",
    "reserve_for_bpp_shipping_return" => "Frete de devolução (reserva)", "reserve_for_payment" => "Reserva para pagamento",
    "fee-release_in_advance" => "Tarifa de antecipação", "payout" => "Saques / transferências", "withdrawal" => "Saques / transferências",
    "chargeback" => "Contestação de cartão (chargeback)", "credit_payment" => "Pagamento de crédito"
  }.freeze

  def amount = net_credit.to_f - net_debit.to_f
end
