class CreateMlItems < ActiveRecord::Migration[8.1]
  def change
    # `item_id` (MLB…) é a PK real, como já vem do Mercado Livre — sem id
    # serial próprio (mesmo padrão de `t.string :state, primary_key: true`
    # usado em ml_oauth_states).
    create_table :ml_items, id: false do |t|
      t.string :item_id, primary_key: true
      t.references :ml_account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.bigint :seller_id, null: false
      t.string :title, collation: "pt-BR-x-icu"
      t.string :status
      t.jsonb :sub_status, null: false, default: []
      t.decimal :price, precision: 12, scale: 2
      t.decimal :original_price, precision: 12, scale: 2
      t.decimal :sale_price, precision: 12, scale: 2
      t.decimal :regular_price, precision: 12, scale: 2
      t.integer :available_quantity
      t.integer :sold_quantity
      t.string :listing_type_id
      t.string :category_id
      t.string :logistic_type
      t.boolean :free_shipping
      t.boolean :catalog_listing
      t.string :sku
      t.integer :variations_count
      t.string :permalink
      t.string :thumbnail
      t.decimal :health, precision: 5, scale: 2
      t.integer :pictures_count
      t.boolean :has_video
      t.jsonb :attrs_filled, null: false, default: []
      t.jsonb :attrs_missing_required, null: false, default: []
      t.jsonb :attrs_missing_main, null: false, default: []
      t.string :brand
      t.string :model
      t.integer :description_len
      t.integer :quality_score
      t.string :quality_level
      t.jsonb :quality_pending, null: false, default: []
      t.decimal :fee_now, precision: 12, scale: 2
      t.decimal :ship_cost, precision: 12, scale: 2
      t.jsonb :price_ref
      t.decimal :fee_at_ref, precision: 12, scale: 2
      t.decimal :ship_at_ref, precision: 12, scale: 2
      t.datetime :date_created
      t.datetime :last_updated
      t.datetime :details_checked_at
      t.datetime :quality_checked_at
      t.datetime :synced_at
    end

    add_index :ml_items, [ :ml_account_id, :status ]
  end
end
