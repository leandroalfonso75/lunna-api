class CreateAiPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_plans, id: :uuid do |t|
      # Sem índice próprio: o único (ml_account_id, item_id) já cobre a busca por conta.
      t.references :ml_account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
      t.string :item_id, null: false
      t.string :status, null: false, default: "pending"
      t.text :text, null: false, default: ""
      t.string :error

      t.timestamps
    end

    add_index :ai_plans, [ :ml_account_id, :item_id ], unique: true
  end
end
