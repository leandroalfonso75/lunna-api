# Reclamações › Devoluções (pedido do usuário em 13/11/2026): "Ok, nota de retorno emitida" tira a devolução de SEM NOTA
# até a próxima rodada de conferência (a diária, às 5h); se a nota não for achada nela, volta para SEM NOTA.
class AddReturnInvoiceDeclaredToMlClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_claims, :return_invoice_declared_at, :datetime
    add_column :ml_claims, :return_invoice_declared_by_id, :uuid
    add_column :ml_claims, :return_invoice_confirmed_check_at, :datetime
  end
end
