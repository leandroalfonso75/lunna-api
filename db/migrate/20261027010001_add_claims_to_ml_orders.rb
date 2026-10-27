# Reclamações/mediações da venda (cancelamento, reclamação, devolução), resumidas para a seção Vendas.
class AddClaimsToMlOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_orders, :claims, :jsonb
    add_column :ml_orders, :claims_synced_at, :datetime
  end
end
