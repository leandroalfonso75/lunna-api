class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.string :ip
      t.string :user_agent

      t.timestamps
    end

    add_index :sessions, :token_digest, unique: true
  end
end
