# Seção Vendas x Ads: gasto de publicidade por anúncio e por dia, para ratear o custo de Ads entre as vendas.
# ml_ad_day_syncs diz quais dias já foram lidos e quando: dia lido só depois de acabar é considerado fechado.
class CreateMlAdItemDailies < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_ad_item_dailies do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :item_id, null: false
      t.date :date, null: false
      t.bigint :campaign_id
      t.decimal :cost, precision: 12, scale: 2, default: 0, null: false
      t.integer :clicks, default: 0, null: false
      t.bigint :prints, default: 0, null: false
      t.decimal :total_amount, precision: 12, scale: 2, default: 0, null: false
      t.integer :units, default: 0, null: false
      t.index [ :ml_account_id, :item_id, :date ], unique: true, name: "index_ml_ad_item_dailies_unique"
      t.index [ :ml_account_id, :date ]
    end

    create_table :ml_ad_day_syncs do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :date, null: false
      t.datetime :fetched_at, null: false
      t.index [ :ml_account_id, :date ], unique: true, name: "index_ml_ad_day_syncs_unique"
    end
  end
end
