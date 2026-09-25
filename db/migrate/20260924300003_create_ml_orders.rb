class CreateMlOrders < ActiveRecord::Migration[8.1]
  def change
    # `order_id` é o id do pedido no Mercado Livre — PK própria, sem serial.
    create_table :ml_orders, id: false do |t|
      t.bigint :order_id, primary_key: true
      t.references :ml_account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :status
      t.datetime :date_created
      t.datetime :date_closed
      t.decimal :total_amount, precision: 12, scale: 2
      t.datetime :synced_at
    end

    add_index :ml_orders, [ :ml_account_id, :date_created ]
  end
end
