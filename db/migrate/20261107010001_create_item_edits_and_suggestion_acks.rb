class CreateItemEditsAndSuggestionAcks < ActiveRecord::Migration[8.1]
  def change
    # Modelo User Products do ML: o título vem do family_name (só editável sem vendas no user product)
    add_column :ml_items, :user_product_id, :string
    add_column :ml_items, :family_name, :string
    add_index :ml_items, :user_product_id

    # Alterações feitas pelo Lunna no anúncio do ML (título e ficha técnica), com antes/depois e o resultado
    create_table :ml_item_edits do |t|
      t.uuid :ml_account_id, null: false
      t.string :item_id, null: false
      t.uuid :user_id
      t.string :kind, null: false
      t.jsonb :before, null: false, default: {}
      t.jsonb :after, null: false, default: {}
      t.boolean :ok, null: false, default: false
      t.string :error
      t.timestamps
    end
    add_index :ml_item_edits, [ :ml_account_id, :item_id ]

    # "Ciente" nas sugestões da Curva ABC: aplicada no ML ou aguardar (volta depois de `until_at` se ainda valer)
    create_table :abc_suggestion_acks do |t|
      t.uuid :ml_account_id, null: false
      t.string :item_id, null: false
      t.string :key, null: false
      t.string :kind, null: false
      t.datetime :until_at, null: false
      t.uuid :user_id
      t.timestamps
    end
    add_index :abc_suggestion_acks, [ :ml_account_id, :item_id, :key ], unique: true
  end
end
