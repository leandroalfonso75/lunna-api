# Pedido de geração de fotos de um anúncio (Curva ABC > Fotos): referências, quantidade, instruções, as imagens
# geradas (ml_generated_photos) e a publicação no Mercado Livre.
class MlPhotoJob < ApplicationRecord
  STATUSES = %w[gerando pronto erro publicado].freeze
  MAX_COUNT = 6
  # "Adicionar foto" (pedido do usuário em 25/11/2026) gera mais uma no mesmo pedido, até o limite de fotos do ML
  MAX_TOTAL = 10

  belongs_to :ml_account
  belongs_to :user, optional: true
  has_many :photos, -> { order(:position) }, class_name: "MlGeneratedPhoto", dependent: :delete_all

  validates :status, inclusion: { in: STATUSES }
  validates :count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_TOTAL }
  validates :count, numericality: { less_than_or_equal_to: MAX_COUNT }, on: :create

  def generated = photos.select { |p| p.kind == "gerada" }
  def uploaded_references = photos.select { |p| p.kind == "referencia" }
end
