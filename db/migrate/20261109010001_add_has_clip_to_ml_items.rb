class AddHasClipToMlItems < ActiveRecord::Migration[8.1]
  def change
    # Vídeo do anúncio no formato atual do ML (clip/shorts), que não aparece em video_id: lido da qualidade do anúncio
    # (regra HAS_SHORTS/UP_HAS_SHORTS: COMPLETED = tem vídeo, PENDING = não tem; nil = ainda não lido)
    add_column :ml_items, :has_clip, :boolean
  end
end
