# Reclamações › Devoluções (pedido do usuário em 13/11/2026): nota fiscal de devolução de cada devolução efetivada.
# Full: a nota "Devolução de mercadorias" que o ML emite no envio da venda; Agência/Flex: a nota de entrada no Olist.
# return_invoice = { number, series, label ("022615-1"), source ("ml" | "olist"), issued_at, key }.
class AddReturnInvoiceToMlClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_claims, :return_invoice, :jsonb
    add_column :ml_claims, :return_invoice_checked_at, :datetime
  end
end
