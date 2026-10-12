class AddFullStock < ActiveRecord::Migration[8.1]
  def change
    # Pares {sku, inventory_id} de cada anúncio (do item e de cada variação): é por
    # eles que o estoque do Full (Mercado Livre) é ligado ao SKU do Olist.
    add_column :ml_items, :inventory_refs, :jsonb, null: false, default: []

    # Estoque do Full (Fulfillment) por inventory_id, lido do Mercado Livre.
    create_table :ml_full_stocks, id: :uuid do |t|
      t.references :ml_account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
      t.string :inventory_id, null: false
      t.integer :available_units, null: false, default: 0
      t.integer :not_available_units, null: false, default: 0
      t.integer :total_units, null: false, default: 0
      t.jsonb :not_available_detail, null: false, default: []
      t.datetime :synced_at, null: false

      t.timestamps
    end
    add_index :ml_full_stocks, [ :ml_account_id, :inventory_id ], unique: true
  end
end
