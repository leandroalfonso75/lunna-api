# Referência fixa da redução de margem por anúncio (27/11/2026, "travar a escada" em Promoções): a tolerância de
# redução é medida contra esta margem, e não contra a promoção do dia. `log` guarda o histórico das trocas de referência.
class CreateMlPromotionDropRefs < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_promotion_drop_refs do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :item_id, null: false
      t.decimal :margin_pct, precision: 6, scale: 2, null: false
      t.datetime :set_at, null: false
      t.string :source, null: false
      t.string :key, null: false
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.jsonb :log, null: false, default: []
      t.timestamps
    end
    add_index :ml_promotion_drop_refs, %i[ml_account_id item_id], unique: true
  end
end
