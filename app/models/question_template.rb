# Resposta padrão da seção Perguntas (por empresa).
class QuestionTemplate < ApplicationRecord
  MAX_BODY = 2000 # limite do Mercado Livre para a resposta de pergunta
  KINDS = { "pergunta" => 2000, "mensagem" => 350 }.freeze # mensagem de pós-venda: até 350 caracteres

  belongs_to :company

  validates :title, presence: true, length: { maximum: 80 }
  validates :body, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validate { errors.add(:body, "pode ter no máximo #{KINDS[kind]} caracteres") if KINDS[kind] && body.to_s.length > KINDS[kind] }

  default_scope { order(:position, :id) }
end
