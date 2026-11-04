# Anúncio em que as fotos foram publicadas (o próprio ou, se ele é de catálogo, o tradicional do mesmo produto).
class AddPublishedItemIdToMlPhotoJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_photo_jobs, :published_item_id, :string
  end
end
