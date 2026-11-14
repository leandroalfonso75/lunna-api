# Seção Estoque › Full (pedido do usuário em 14/11/2026): recomendações de reposição do Full por User Product, lidas da
# API "Planejamento de reposição para Fulfillment" do ML (GET /marketplace/fbm/sellers/{id}/user-products/replenishment).
class CreateMlFullReplenishments < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_full_replenishments do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :user_product_id, null: false
      t.string :inventory_id
      t.string :seller_sku
      t.jsonb :tags, null: false, default: []
      t.integer :total_stock
      t.string :shipping_urgency
      t.integer :minimum_distributable_stock
      t.integer :units_30d
      t.decimal :gmv_30d, precision: 14, scale: 2
      t.jsonb :sales_history, null: false, default: []
      t.string :recommendation_type
      t.integer :suggested_quantity
      t.string :replenishment_deadline
      t.integer :replenishment_frequency
      t.jsonb :benefits, null: false, default: []
      t.datetime :synced_at, null: false
      t.timestamps
    end
    add_index :ml_full_replenishments, %i[ml_account_id user_product_id], unique: true
    add_index :ml_full_replenishments, %i[ml_account_id seller_sku]
    add_column :ml_accounts, :full_replenishment_synced_at, :datetime
  end
end
