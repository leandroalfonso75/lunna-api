# Uma ação do Lunna numa promoção do Mercado Livre (ver Painel::PromotionActions).
class MlPromotionAction < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true
  belongs_to :run, class_name: "MlPromotionRun", optional: true, inverse_of: :actions

  # Ações que mudam a promoção do anúncio no ML; uma delas depois de uma troca programada a substitui.
  CHANGE_KINDS = %w[aderir ajustar_preco trocar sair agendar].freeze

  # Trocas programadas ainda por vir: "agendar" que deu certo, com a hora no futuro, e sem nenhuma mudança que deu
  # certo no anúncio depois dela (ex.: o administrador aplicou a cabível pela tela antes da hora programada).
  scope :pending_schedules, -> {
    where(kind: "agendar", ok: true).where("ml_promotion_actions.effective_at > ?", Time.current)
      .where(<<~SQL.squish, CHANGE_KINDS)
        NOT EXISTS (SELECT 1 FROM ml_promotion_actions later WHERE later.ml_account_id = ml_promotion_actions.ml_account_id
          AND later.item_id = ml_promotion_actions.item_id AND later.ok = TRUE AND later.kind IN (?)
          AND later.source <> 'simulacao' AND later.created_at > ml_promotion_actions.created_at)
      SQL
  }
end
