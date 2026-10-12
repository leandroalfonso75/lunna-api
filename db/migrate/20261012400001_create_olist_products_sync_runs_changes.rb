class CreateOlistProductsSyncRunsChanges < ActiveRecord::Migration[8.1]
  def change
    # Cópia local dos produtos do Olist ERP (atualizada pela sincronização).
    create_table :olist_products, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :olist_id, null: false
      t.string :sku
      t.string :description
      t.string :kind            # K kit, S simples, V com variações, F fabricado, M matéria-prima
      t.string :status          # A ativo, I inativo, E excluído
      t.string :variation_kind  # N normal, P pai, V variação
      t.string :unit
      t.string :gtin
      t.decimal :price, precision: 14, scale: 2
      t.decimal :promo_price, precision: 14, scale: 2
      t.decimal :cost_price, precision: 14, scale: 2
      t.decimal :avg_cost_price, precision: 14, scale: 2
      t.decimal :stock_balance, precision: 14, scale: 3
      t.decimal :stock_reserved, precision: 14, scale: 3
      t.decimal :stock_available, precision: 14, scale: 3
      t.string :stock_location
      t.jsonb :stock_deposits, null: false, default: []
      t.datetime :olist_created_at
      t.datetime :olist_updated_at
      t.datetime :synced_at, null: false

      t.timestamps
    end
    add_index :olist_products, [ :company_id, :olist_id ], unique: true
    add_index :olist_products, [ :company_id, :sku ]
    add_index :olist_products, [ :company_id, :status ]

    # Uma linha por rodada de sincronização (automática ou pedida pelo usuário).
    create_table :olist_sync_runs, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
      t.references :requested_by_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :trigger, null: false, default: "auto"   # auto | manual
      t.string :status, null: false, default: "running" # running | success | failed
      t.integer :products_count
      t.string :error
      t.datetime :started_at, null: false
      t.datetime :finished_at

      t.timestamps
    end
    add_index :olist_sync_runs, [ :company_id, :started_at ]

    # Registro de toda alteração feita no Olist pelo Lunna (quem, o quê, quando, antes e depois).
    create_table :olist_changes, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.bigint :olist_product_id, null: false
      t.string :kind, null: false                     # price | stock
      t.jsonb :before, null: false, default: {}
      t.jsonb :request, null: false, default: {}
      t.jsonb :response, null: false, default: {}
      t.string :status, null: false, default: "pending" # pending | done | failed
      t.string :error

      t.timestamps
    end
    add_index :olist_changes, [ :company_id, :created_at ]
  end
end
