# Recomendação de reposição do Full de um User Product (seção Estoque › Full). Ver Ml::Sync::FullReplenishment.
class MlFullReplenishment < ApplicationRecord
  belongs_to :ml_account

  # Ordem de urgência do ML (o que vier diferente fica no fim).
  URGENCY_ORDER = %w[URGENT THIS_WEEK NEXT_WEEK NO_URGENCY].freeze
  URGENCY_LABELS = { "URGENT" => "Urgente", "THIS_WEEK" => "Esta semana", "NEXT_WEEK" => "Próxima semana", "NO_URGENCY" => "Sem urgência" }.freeze
  DEADLINE_LABELS = { "THIS_WEEK" => "esta semana", "NEXT_WEEK" => "próxima semana", "NOT_REPLENISHMENT_NEEDED" => "sem necessidade" }.freeze

  def replenish? = recommendation_type == "REPLENISH"
end
