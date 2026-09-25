class CreateItemMetrics < ActiveRecord::Migration[8.1]
  def change
    # PK é o item_id do ML (docs/METRICS.md), igual a ml_items. A tabela
    # inteira da conta é regravada por Painel::ItemMetrics.refresh
    # (delete_all + insert_all) a cada sincronização; sem FK pra ml_items
    # porque as duas tabelas são recarregadas em momentos diferentes.
    create_table :item_metrics, id: false do |t|
      t.string :item_id, primary_key: true
      t.references :ml_account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :title, collation: "pt-BR-x-icu"
      t.string :status
      t.string :sku
      t.string :listing_type
      t.boolean :full
      t.boolean :free_shipping
      t.boolean :catalog
      t.integer :variations
      t.decimal :price, precision: 12, scale: 2
      t.decimal :original_price, precision: 12, scale: 2
      t.integer :stock
      t.integer :quality_score

      t.integer :visits_7d, null: false, default: 0
      t.integer :prev_visits_7d, null: false, default: 0
      t.integer :visits_30d, null: false, default: 0
      t.integer :prev_visits_30d, null: false, default: 0

      t.integer :units_today, null: false, default: 0
      t.integer :units_7d, null: false, default: 0
      t.integer :prev_units_7d, null: false, default: 0
      t.integer :units_30d, null: false, default: 0
      t.integer :prev_units_30d, null: false, default: 0

      t.decimal :revenue_7d, precision: 12, scale: 2, null: false, default: 0
      t.decimal :prev_revenue_7d, precision: 12, scale: 2, null: false, default: 0
      t.decimal :revenue_30d, precision: 12, scale: 2, null: false, default: 0
      t.decimal :prev_revenue_30d, precision: 12, scale: 2, null: false, default: 0

      t.decimal :net_after_fee_7d, precision: 12, scale: 2, null: false, default: 0
      t.decimal :fees_30d, precision: 12, scale: 2, null: false, default: 0

      t.decimal :conversion_7d, precision: 8, scale: 2
      t.decimal :prev_conversion_7d, precision: 8, scale: 2
      t.decimal :conversion_30d, precision: 8, scale: 2
      t.decimal :prev_conversion_30d, precision: 8, scale: 2

      # Nil quando u7 = 0 e pu7 = 0 (ninguém vendeu nas duas semanas).
      t.integer :units_delta
      # Nil quando u7 (u30) = 0 — sem venda não dá pra estimar cobertura.
      t.decimal :coverage_days, precision: 10, scale: 1
      t.decimal :coverage_30d, precision: 10, scale: 1

      t.datetime :computed_at
    end

    add_index :item_metrics, [ :ml_account_id, :status ]
    # Colunas ordenáveis mais usadas pela tabela (padrão units_7d) e pela
    # Curva ABC (revenue_30d) — sempre filtradas por conta primeiro.
    add_index :item_metrics, [ :ml_account_id, :units_7d ]
    add_index :item_metrics, [ :ml_account_id, :revenue_30d ]
  end
end
