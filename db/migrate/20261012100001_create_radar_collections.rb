class CreateRadarCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :radar_collections, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :requested_by_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :category_path, null: false
      t.string :status, null: false, default: "requested"
      t.string :error
      t.integer :items_count
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    # No máximo um pedido em aberto por empresa e categoria.
    add_index :radar_collections, [ :company_id, :category_path ],
      unique: true, where: "status IN ('requested', 'collecting')",
      name: "index_radar_collections_one_active_per_category"
  end
end
