# Notas de devolução em lote (13/11/2026): meses já lidos no download em lote de documentos fiscais do ML ("YYYY-MM").
class AddReturnInvoiceMonthsToMlAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_accounts, :return_invoice_months, :jsonb, null: false, default: []
  end
end
