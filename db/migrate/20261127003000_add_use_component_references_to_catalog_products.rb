# Kit (pedido do usuário em 26/11/2026): "Usar como referências os produtos que formarão o(s) kit(s)": a IA usa a
# descrição, a ficha técnica e as especificações dos componentes e ignora os campos Links e Texto.
class AddUseComponentReferencesToCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_products, :use_component_references, :boolean, null: false, default: false
  end
end
