# Curva ABC > Fotos (pedido do usuário em 04/11/2026): geração de imagens do anúncio pela OpenRouter, aprovação pelo
# usuário e publicação no anúncio do Mercado Livre.
class CreateMlPhotoJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :ai_image_model, :string, default: "google/gemini-2.5-flash-image"

    create_table :ml_photo_jobs do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :item_id, null: false
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.integer :count, null: false
      t.text :instructions
      t.jsonb :reference_urls, null: false, default: [] # fotos do próprio anúncio usadas como referência
      t.string :model
      t.string :status, null: false, default: "gerando" # gerando, pronto, erro, publicado
      t.text :error
      t.datetime :published_at
      t.text :publish_error
      t.timestamps
    end
    add_index :ml_photo_jobs, %i[ml_account_id item_id]

    create_table :ml_generated_photos do |t|
      t.references :ml_photo_job, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false, default: "gerada" # gerada | referencia (anexada pelo usuário)
      t.integer :position, null: false, default: 0
      t.string :mime, null: false
      t.binary :data, null: false
      t.boolean :approved, null: false, default: false
      t.string :ml_picture_id # depois de publicada
      t.timestamps
    end
  end
end
