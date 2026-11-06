# Pagamento recebido no Mercado Pago (venda do ML ou frete pago pelo comprador), com as taxas descontadas e o líquido.
class MpPayment < ApplicationRecord
  belongs_to :ml_account
end
