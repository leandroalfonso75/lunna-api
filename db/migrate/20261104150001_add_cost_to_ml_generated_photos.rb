# Custo de cada imagem gerada, em US$, como a OpenRouter informa na resposta (usage.cost).
class AddCostToMlGeneratedPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_generated_photos, :cost_usd, :decimal, precision: 10, scale: 6
    add_column :ml_generated_photos, :model, :string
  end
end
