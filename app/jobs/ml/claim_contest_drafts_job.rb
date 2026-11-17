# A cada hora (config/recurring.yml): escreve com IA as contestações pendentes que ainda não têm texto da IA, ou cuja
# reclamação mudou depois dele (Painel::ClaimContest.generate_missing!). Pedido do usuário em 17/11/2026.
module Ml
  class ClaimContestDraftsJob < ApplicationJob
    limits_concurrency to: 1, key: ->(account_id = nil) { "claim-contest-drafts-#{account_id}" }, duration: 30.minutes, on_conflict: :discard

    def perform(account_id = nil)
      return MlAccount.active.find_each { |a| self.class.perform_later(a.id) } if account_id.nil?

      account = MlAccount.find_by(id: account_id)
      return if account.nil? || account.company.openrouter_api_key.blank?

      Painel::ClaimContest.generate_missing!(account)
    end
  end
end
