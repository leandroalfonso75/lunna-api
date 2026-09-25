class CreateMlSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_sync_runs, id: :uuid do |t|
      t.references :ml_account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.boolean :ok
      t.integer :items
      t.integer :orders
      t.text :detail
    end

    add_index :ml_sync_runs, [ :ml_account_id, :started_at ]
  end
end
