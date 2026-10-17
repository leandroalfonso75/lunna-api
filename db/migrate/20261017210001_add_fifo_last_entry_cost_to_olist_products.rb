# Custo da última entrada de estoque com preço: serve de custo quando não há saldo em camadas
# (produto zerado ou com histórico que não fecha) mas o produto continua sendo vendido.
class AddFifoLastEntryCostToOlistProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :olist_products, :fifo_last_entry_cost, :decimal, precision: 12, scale: 4
  end
end
