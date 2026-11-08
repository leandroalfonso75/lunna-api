# Pergunta de um comprador num anúncio do Mercado Livre (seção Perguntas).
class MlQuestion < ApplicationRecord
  STATUS_LABELS = {
    "UNANSWERED" => [ "Sem resposta", "warn" ], "ANSWERED" => [ "Respondida", "success" ],
    "UNDER_REVIEW" => [ "Em revisão no ML", "neutral" ], "CLOSED_UNANSWERED" => [ "Encerrada sem resposta", "danger" ],
    "BANNED" => [ "Bloqueada pelo ML", "danger" ], "DELETED" => [ "Apagada", "neutral" ], "DISABLED" => [ "Desativada", "neutral" ]
  }.freeze

  belongs_to :ml_account

  scope :unanswered, -> { where(status: "UNANSWERED") }

  def answerable? = status == "UNANSWERED"
end
