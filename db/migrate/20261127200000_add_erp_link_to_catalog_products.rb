# Migração dos produtos do ERP (27/11/2026): a ficha completa do Lunna (catalog_products) passa a guardar produtos vindos
# do ERP, presos ao id deles no ERP. O ERP manda nos dados; o Lunna copia. A cópia sincronizada (olist_products), o custo
# PEPS e o histórico de entradas não mudam.
class AddErpLinkToCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_products, :source, :string, null: false, default: "lunna"
    add_column :catalog_products, :erp_key, :string
    add_column :catalog_products, :erp_id, :bigint
    add_column :catalog_products, :erp_synced_at, :datetime
    add_column :catalog_products, :erp_payload, :jsonb, null: false, default: {}
    add_column :catalog_products, :erp_warnings, :jsonb, null: false, default: []
    add_index :catalog_products, %i[company_id erp_key erp_id], unique: true, where: "erp_id IS NOT NULL", name: "index_catalog_products_on_erp"
    add_column :catalog_product_assets, :source_url, :string
  end
end
