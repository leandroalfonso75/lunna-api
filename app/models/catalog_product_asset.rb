# Imagem de um produto do Lunna: referência anexada pelo usuário ou foto do produto/variação. Bytes no banco.
class CatalogProductAsset < ApplicationRecord
  MAX_BYTES = 8.megabytes

  belongs_to :catalog_product

  validates :kind, inclusion: { in: %w[referencia foto] }
  validates :mime, inclusion: { in: %w[image/png image/jpeg image/webp] }

  def data_url = "data:#{mime};base64,#{Base64.strict_encode64(data)}"
end
