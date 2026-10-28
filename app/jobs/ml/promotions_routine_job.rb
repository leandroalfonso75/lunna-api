# Rotina das 03:00 da seção Promoções (agendada em config/recurring.yml) e "Simular agora" da tela.
# Agendada: roda para cada conta ativa cuja empresa ligou a rotina, no modo escolhido em Configurações.
# Manual (account_id): roda só naquela conta, sempre em simulação.
module Ml
  class PromotionsRoutineJob < ApplicationJob
    queue_as :default

    def perform(account_id = nil, user_id = nil)
      if account_id
        account = MlAccount.active.find_by(id: account_id)
        Painel::PromotionRoutine.call(account, mode: "simulation", trigger: "manual", user: User.find_by(id: user_id)) if account
        return
      end

      MlAccount.active.includes(:company).find_each do |account|
        next unless account.company.promo_routine_enabled

        Painel::PromotionRoutine.call(account, mode: account.company.promo_routine_mode, trigger: "agendada")
      rescue StandardError => e
        Rails.logger.error("Ml::PromotionsRoutineJob conta #{account.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
