# Uma imagem do pedido de fotos: gerada pela IA ou anexada pelo usuário como referência. Guardada no banco (bytes).
class MlGeneratedPhoto < ApplicationRecord
  belongs_to :ml_photo_job

  validates :kind, inclusion: { in: %w[gerada referencia] }

  def data_url = "data:#{mime};base64,#{Base64.strict_encode64(data)}"
end
