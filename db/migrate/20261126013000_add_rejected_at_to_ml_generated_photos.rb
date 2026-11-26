# Reprovar uma imagem gerada (pedido do usuário em 25/11/2026): some da tela e não é publicada, mas continua no
# pedido para o custo da geração seguir contado.
class AddRejectedAtToMlGeneratedPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_generated_photos, :rejected_at, :datetime
  end
end
