# Resposta padrão da seção Perguntas (por empresa).
class QuestionTemplate < ApplicationRecord
  MAX_BODY = 2000 # limite do Mercado Livre para a resposta

  belongs_to :company

  validates :title, presence: true, length: { maximum: 80 }
  validates :body, presence: true, length: { maximum: MAX_BODY }

  default_scope { order(:position, :id) }
end
