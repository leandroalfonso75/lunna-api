# Plano de ação com IA de um anúncio (DECISOES §10): uma linha por
# (conta, anúncio), sobrescrita a cada "Gerar de novo". `Ai::ActionPlanJob`
# grava o texto aos poucos e o front lê por polling (`GET /api/items/:id/ai-plan`).
class AiPlan < ApplicationRecord
  ACTIVE = %w[pending running].freeze
  # Sem nenhuma gravação do job há tanto tempo (worker caiu, deploy no meio):
  # a leitura passa a tratar como erro em vez de deixar o front esperando.
  STALE_AFTER = 5.minutes
  STALE_ERROR = "A geração foi interrompida. Tente de novo."

  belongs_to :ml_account

  def active? = ACTIVE.include?(status)

  def stale? = persisted? && active? && updated_at < STALE_AFTER.ago
end
