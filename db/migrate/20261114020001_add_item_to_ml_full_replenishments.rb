# Estoque › Full (14/11/2026): anúncios do formato antigo (com variações, sem User Product) não vêm na API de reposição do
# ML. O Lunna inclui o estoque Full deles (uma linha por inventory_id), com o anúncio e a variação; sem recomendação do ML.
class AddItemToMlFullReplenishments < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_full_replenishments, :item_id, :string
    add_column :ml_full_replenishments, :variation_label, :string
    add_column :ml_full_replenishments, :source, :string, null: false, default: "ml"
  end
end
