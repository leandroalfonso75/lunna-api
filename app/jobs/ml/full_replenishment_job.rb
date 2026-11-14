# A cada 6 horas (config/recurring.yml): recomendações de reposição do Full de cada conta (Ml::Sync::FullReplenishment).
module Ml
  class FullReplenishmentJob < ApplicationJob
    limits_concurrency to: 1, key: ->(account_id = nil) { "full-replenishment-#{account_id}" }, duration: 30.minutes, on_conflict: :discard

    def perform(account_id = nil)
      return MlAccount.active.find_each { |a| self.class.perform_later(a.id) } if account_id.nil?

      account = MlAccount.find_by(id: account_id)
      return unless account

      Ml::OAuth.refresh!(account)
      Ml::Sync::FullReplenishment.call(Ml::Client.new(access_token: account.access_token), account)
    end
  end
end
