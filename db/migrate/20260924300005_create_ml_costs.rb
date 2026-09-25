class CreateMlCosts < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_costs do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :sku, null: false
      t.decimal :cost, precision: 12, scale: 2
      t.decimal :extra, precision: 12, scale: 2, null: false, default: 0
      t.string :source

      t.timestamps
    end

    add_index :ml_costs, [ :company_id, :sku ], unique: true
  end
end
