# Kit = 1 produto com variações + 1 produto simples (pedido do usuário em 26/11/2026): informa o SKU do simples e o SKU
# pai do produto com variações; o Lunna importa as variações do pai e cada uma vira um kit (variação + simples). O
# resultado usa a grade de variações (cada linha é kit) e os itens comuns (o simples).
class AddKitWithVariationsToCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_products, :kit_with_variations, :boolean, null: false, default: false
    add_column :catalog_products, :kit_simple_sku, :string
    add_column :catalog_products, :kit_simple_quantity, :decimal, precision: 10, scale: 3, null: false, default: 1
    add_column :catalog_products, :kit_parent_sku, :string
    add_column :catalog_products, :kit_parent_quantity, :decimal, precision: 10, scale: 3, null: false, default: 1
  end
end
