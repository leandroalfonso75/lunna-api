# Kit (pedido do usuário em 27/11/2026): "Usar como referências as fotos dos produtos que formarão o(s) kit(s)": a IA
# (e a galeria, na etapa de imagens) usa as fotos dos anúncios dos componentes no lugar das anexadas/coladas.
class AddUseComponentPhotosToCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_products, :use_component_photos, :boolean, null: false, default: false
  end
end
