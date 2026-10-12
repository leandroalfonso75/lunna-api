class CreateOlistConnections < ActiveRecord::Migration[8.1]
  def change
    # Uma conexão do Olist ERP por empresa (OAuth2, API v3).
    create_table :olist_connections, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :connected_by_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      # Cifrados (Active Record Encryption), como os tokens do Mercado Livre.
      t.text :access_token, null: false
      t.text :refresh_token, null: false
      t.datetime :expires_at
      # O refresh token do Olist vale 1 dia: passou disso, só reconectando.
      t.datetime :refresh_expires_at
      t.string :status, null: false, default: "active"
      t.string :last_error

      t.timestamps
    end

    # State de uso único do fluxo OAuth (mesmo desenho do ml_oauth_states).
    create_table :olist_oauth_states, id: false do |t|
      t.string :state, null: false, primary_key: true
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
