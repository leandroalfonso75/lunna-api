# Seção Promoções: promoções da Central de Promoções do Mercado Livre, as ofertas de cada anúncio (candidato ou ativo)
# e a margem mínima/máxima configurada por anúncio.
class CreateMlPromotions < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_promotions do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :promotion_id, null: false
      t.string :promotion_type, null: false
      t.string :sub_type
      t.string :name
      t.string :status
      t.datetime :start_date
      t.datetime :finish_date
      t.datetime :deadline_date
      t.jsonb :payload
      t.datetime :synced_at
      t.timestamps
    end
    add_index :ml_promotions, %i[ml_account_id promotion_id], unique: true, name: "index_ml_promotions_unique"

    # Uma linha por anúncio e oferta (/seller-promotions/items/{id}). PRICE_DISCOUNT (desconto próprio) não tem id.
    create_table :ml_promotion_offers do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :item_id, null: false
      t.string :promotion_id
      t.string :promotion_type, null: false
      t.string :sub_type
      t.string :name
      t.string :status
      t.decimal :price, precision: 12, scale: 2
      t.decimal :original_price, precision: 12, scale: 2
      t.decimal :min_price, precision: 12, scale: 2
      t.decimal :max_price, precision: 12, scale: 2
      t.decimal :max_top_price, precision: 12, scale: 2
      t.decimal :suggested_price, precision: 12, scale: 2
      t.decimal :fixed_amount, precision: 12, scale: 2
      t.decimal :meli_percentage, precision: 6, scale: 2
      t.decimal :seller_percentage, precision: 6, scale: 2
      t.datetime :start_date
      t.datetime :finish_date
      t.jsonb :fees # tarifa do ML no preço da oferta: { price, sale_fee, percentage_fee, fixed_fee }
      t.jsonb :payload
      t.datetime :synced_at
      t.timestamps
    end
    add_index :ml_promotion_offers, %i[ml_account_id item_id]
    add_index :ml_promotion_offers, %i[ml_account_id promotion_id]

    create_table :ml_promotion_settings do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :item_id, null: false
      t.string :sku
      t.decimal :min_margin_pct, precision: 6, scale: 2
      t.decimal :max_margin_pct, precision: 6, scale: 2
      t.boolean :apply_to_sku, null: false, default: false
      t.boolean :automation_enabled, null: false, default: true
      t.references :updated_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :ml_promotion_settings, %i[ml_account_id item_id], unique: true, name: "index_ml_promotion_settings_unique"

    add_column :ml_accounts, :promotions_synced_at, :datetime
  end
end
