class AddProfitInputs < ActiveRecord::Migration[8.1]
  def change
    # Detalhe da tarifa do ML no preço atual (sale_fee_details do listing_prices): separa a
    # comissão (percentual) da taxa fixa e do custo de financiamento.
    add_column :ml_items, :fee_details, :jsonb

    # Despesas fixas, em % do preço de venda. Por enquanto 3%; vai ganhar um campo
    # editável em outra página.
    add_column :companies, :fixed_expenses_pct, :decimal, precision: 6, scale: 2, null: false, default: 3.0
  end
end
