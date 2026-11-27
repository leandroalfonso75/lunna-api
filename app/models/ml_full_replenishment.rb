# Recomendação de reposição do Full de um User Product (seção Estoque › Full). Ver Ml::Sync::FullReplenishment.
class MlFullReplenishment < ApplicationRecord
  belongs_to :ml_account

  # Ordem de urgência do ML (o que vier diferente fica no fim).
  # IN_TWO_WEEKS apareceu cru na tela em 27/11/2026: todo valor conhecido tem nome em português e o desconhecido vira
  # um texto legível (nunca o código do Mercado Livre).
  URGENCY_ORDER = %w[URGENT THIS_WEEK NEXT_WEEK IN_TWO_WEEKS NO_URGENCY].freeze
  URGENCY_LABELS = { "URGENT" => "Urgente", "THIS_WEEK" => "Esta semana", "NEXT_WEEK" => "Próxima semana",
                     "IN_TWO_WEEKS" => "Em duas semanas", "NO_URGENCY" => "Sem urgência" }.freeze
  DEADLINE_LABELS = { "THIS_WEEK" => "esta semana", "NEXT_WEEK" => "próxima semana", "IN_TWO_WEEKS" => "em duas semanas",
                      "NOT_REPLENISHMENT_NEEDED" => "sem necessidade" }.freeze
  UNKNOWN_URGENCY = "Prazo não classificado".freeze

  def self.urgency_label(code)
    return nil if code.blank?

    URGENCY_LABELS[code] || UNKNOWN_URGENCY
  end

  def self.deadline_label(code)
    return nil if code.blank?

    DEADLINE_LABELS[code] || "prazo não classificado"
  end

  def replenish? = recommendation_type == "REPLENISH"
end
