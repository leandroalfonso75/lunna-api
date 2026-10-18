# Seção Ads: campanhas de Product Ads, anúncios em campanha e métricas por dia (últimos 3 meses).
class CreateMlAds < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_ad_campaigns, primary_key: [ :ml_account_id, :campaign_id ] do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :campaign_id, null: false
      t.string :name
      t.string :status
      t.string :strategy
      t.string :channel
      t.decimal :acos_target, precision: 8, scale: 2
      t.decimal :roas_target, precision: 8, scale: 2
      t.decimal :budget, precision: 12, scale: 2
      t.decimal :daily_budget, precision: 12, scale: 2
      t.boolean :automatic_budget
      t.datetime :date_created
      t.datetime :last_updated
      t.datetime :synced_at
      t.timestamps
    end

    create_table :ml_ad_items, primary_key: [ :ml_account_id, :item_id ] do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :item_id, null: false
      t.bigint :campaign_id
      t.bigint :ad_group_id
      t.string :title
      t.string :status
      t.decimal :price, precision: 12, scale: 2
      t.string :thumbnail
      t.string :permalink
      t.string :listing_type_id
      t.string :logistic_type
      t.boolean :catalog_listing
      t.boolean :buy_box_winner
      t.boolean :recommended
      t.boolean :has_discount
      t.string :condition
      t.datetime :date_created
      t.jsonb :metrics, null: false, default: {}
      t.datetime :synced_at
      t.timestamps
      t.index [ :ml_account_id, :campaign_id ]
    end

    create_table :ml_ad_daily_metrics do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :campaign_id, null: false
      t.date :date, null: false
      t.integer :clicks, default: 0, null: false
      t.bigint :prints, default: 0, null: false
      t.decimal :cost, precision: 12, scale: 2, default: 0, null: false
      t.decimal :direct_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :indirect_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :total_amount, precision: 12, scale: 2, default: 0, null: false
      t.integer :direct_units, default: 0, null: false
      t.integer :indirect_units, default: 0, null: false
      t.integer :units, default: 0, null: false
      t.integer :organic_units, default: 0, null: false
      t.decimal :organic_amount, precision: 12, scale: 2, default: 0, null: false
      t.index [ :ml_account_id, :campaign_id, :date ], unique: true, name: "index_ml_ad_daily_unique"
    end

    add_column :ml_accounts, :ads_synced_at, :datetime
  end
end
