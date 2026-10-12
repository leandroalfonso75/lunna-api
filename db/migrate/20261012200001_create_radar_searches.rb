class CreateRadarSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :radar_searches, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :category_path, null: false
      # Filtros usados na pesquisa, como a tela os enviou (reabrir a consulta os reaplica).
      t.jsonb :filters, null: false, default: {}
      # Dia da base de dados consultada (data da coleta).
      t.date :data_ref
      t.integer :total_items, null: false, default: 0
      t.bigint :total_sold, null: false, default: 0
      t.decimal :total_revenue, precision: 16, scale: 2, null: false, default: 0
      t.decimal :median_price, precision: 12, scale: 2, null: false, default: 0

      t.timestamps
    end

    add_index :radar_searches, [ :company_id, :created_at ]
  end
end
