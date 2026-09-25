class CreateMlItemVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_item_visits, primary_key: [ :item_id, :day ] do |t|
      t.string :item_id, null: false
      t.references :ml_account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.date :day, null: false
      t.integer :visits, null: false
    end

    add_index :ml_item_visits, [ :ml_account_id, :day ]
  end
end
