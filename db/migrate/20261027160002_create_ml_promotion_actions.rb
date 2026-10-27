# Histórico do que o Lunna fez nas promoções do Mercado Livre (aderir, ajustar preço, sair, trocar), pela tela ou
# pela rotina das 03:00: antes e depois, margem e resposta do ML.
class CreateMlPromotionActions < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_promotion_actions do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :item_id, null: false
      t.string :kind, null: false   # aderir | ajustar_preco | trocar | sair
      t.string :source, null: false # tela | lote | rotina | simulacao
      t.string :from_promotion_id
      t.string :from_type
      t.string :from_name
      t.decimal :from_price, precision: 12, scale: 2
      t.decimal :from_margin_pct, precision: 8, scale: 2
      t.string :to_promotion_id
      t.string :to_type
      t.string :to_name
      t.decimal :to_price, precision: 12, scale: 2
      t.decimal :to_margin_pct, precision: 8, scale: 2
      t.decimal :gain, precision: 12, scale: 2
      t.boolean :ok, null: false, default: false
      t.string :error
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :ml_promotion_actions, %i[ml_account_id created_at]
  end
end
