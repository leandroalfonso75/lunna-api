# Conferência de um anúncio de catálogo depois que a automação mudou o preço (Painel::CatalogCheck).
class MlCatalogCheck < ApplicationRecord
  belongs_to :ml_account
  belongs_to :action, class_name: "MlPromotionAction", optional: true

  STATUSES = %w[aguardando ganhando revertido analise_manual resolvido].freeze
  validates :status, inclusion: { in: STATUSES }
end
