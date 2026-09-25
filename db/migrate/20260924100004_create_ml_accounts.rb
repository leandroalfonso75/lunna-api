class CreateMlAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_accounts, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.bigint :seller_id, null: false
      t.string :nickname
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.string :scope
      t.string :status, null: false, default: "active"
      t.text :last_error
      t.datetime :orders_backfilled_at
      t.datetime :visits_synced_at
      t.references :connected_by_user, null: true, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :ml_accounts, :seller_id, unique: true
  end
end
