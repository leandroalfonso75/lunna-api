class AddCatalogStatusToMlItems < ActiveRecord::Migration[8.1]
  def change
    # Anúncio de catálogo: se está ganhando a vitrine e o preço para ganhar (/items/{id}/price_to_win)
    add_column :ml_items, :catalog_status, :string
    add_column :ml_items, :catalog_price_to_win, :decimal, precision: 12, scale: 2
    add_column :ml_items, :catalog_winner_price, :decimal, precision: 12, scale: 2
    add_column :ml_items, :catalog_reasons, :jsonb, default: [], null: false
    add_column :ml_items, :catalog_checked_at, :datetime
  end
end
