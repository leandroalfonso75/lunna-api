class CreateMlOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_order_items, primary_key: [ :order_id, :item_id ] do |t|
      t.bigint :order_id, null: false
      t.string :item_id, null: false
      t.integer :quantity
      t.decimal :unit_price, precision: 12, scale: 2
      t.decimal :sale_fee, precision: 12, scale: 2
    end

    # Sem FK para ml_items: um pedido pode citar um anúncio que não está
    # mais na lista (DECISOES/SPEC 3).
    add_foreign_key :ml_order_items, :ml_orders, column: :order_id, primary_key: :order_id, on_delete: :cascade
    add_index :ml_order_items, :item_id
  end
end
