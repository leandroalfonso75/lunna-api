class AddFifoCostToOlist < ActiveRecord::Migration[8.1]
  def change
    # Movimentações de estoque do Olist (Suprimentos > Controle de Estoque): é nelas que
    # está o custo informado a cada entrada. Base do cálculo PEPS.
    create_table :olist_stock_movements, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :olist_product_id, null: false
      t.bigint :movement_id, null: false
      t.bigint :deposit_id
      t.string :kind, null: false             # E entrada, S saída, B balanço
      t.decimal :quantity, precision: 14, scale: 3, null: false, default: 0
      t.decimal :price, precision: 14, scale: 4
      t.datetime :moved_at
      t.string :origin
      t.string :note

      t.timestamps
    end
    add_index :olist_stock_movements, [ :company_id, :olist_product_id, :movement_id ], unique: true, name: "index_olist_movements_unique"
    add_index :olist_stock_movements, [ :company_id, :olist_product_id, :moved_at ], name: "index_olist_movements_by_product_date"

    change_table :olist_products, bulk: true do |t|
      t.decimal :fifo_unit_cost, precision: 14, scale: 4          # custo da próxima saída (camada mais antiga com saldo)
      t.decimal :fifo_stock_value, precision: 16, scale: 2        # soma das camadas com custo informado
      t.decimal :fifo_units, precision: 14, scale: 3              # unidades em camadas (estoque rastreado)
      t.decimal :fifo_units_without_cost, precision: 14, scale: 3 # unidades em estoque cuja entrada não tem custo
      t.jsonb :fifo_layers, null: false, default: []              # camadas com saldo (entrada, restante, custo)
      t.decimal :fifo_shortfall, precision: 14, scale: 3          # saídas sem entrada correspondente no histórico
      t.decimal :fifo_balance_at_calc, precision: 14, scale: 3    # saldo do Olist quando o PEPS foi calculado
      t.datetime :fifo_calculated_at
      t.datetime :movements_synced_at
    end

    # Estado da leitura das movimentações (ok / forbidden = app sem permissão / error).
    add_column :olist_connections, :costs_status, :string
    add_column :olist_connections, :costs_checked_at, :datetime
  end
end
