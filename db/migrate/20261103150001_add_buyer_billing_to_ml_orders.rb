class AddBuyerBillingToMlOrders < ActiveRecord::Migration[8.1]
  def change
    # Coluna "Cliente" de Vendas (pedido do usuário em 03/11/2026): nome, CPF/CNPJ e cidade/UF do faturamento.
    # Rua, número, bairro, CEP e telefone continuam fora.
    add_column :ml_orders, :buyer_name, :string
    add_column :ml_orders, :buyer_doc_type, :string
    add_column :ml_orders, :buyer_doc_number, :string
    add_column :ml_orders, :buyer_city, :string
    add_column :ml_orders, :buyer_state, :string
    add_column :ml_orders, :billing_synced_at, :datetime
  end
end
