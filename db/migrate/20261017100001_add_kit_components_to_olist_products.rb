class AddKitComponentsToOlistProducts < ActiveRecord::Migration[8.1]
  def change
    # Composição de um KIT do Olist (GET /produtos/{id}/kit): [{ id, sku, quantity }].
    # O custo e o estoque do kit saem dos componentes.
    add_column :olist_products, :kit_components, :jsonb, null: false, default: []
    add_column :olist_products, :kit_checked_at, :datetime
  end
end
