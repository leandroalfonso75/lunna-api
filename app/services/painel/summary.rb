# Resumo de status dos anúncios (SPEC 7.1) sobre ml_items.
module Painel
  class Summary
    def self.call(account) = new(account).call

    def initialize(account)
      @account = account
    end

    def call
      counts = @account.ml_items.group(:status).count

      {
        total: counts.values.sum,
        active: counts["active"].to_i,
        paused: counts["paused"].to_i,
        closed: counts["closed"].to_i + counts["inactive"].to_i,
        under_review: counts["under_review"].to_i
      }
    end
  end
end
