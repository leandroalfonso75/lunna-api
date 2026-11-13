# Uma vez por dia (config/recurring.yml): notas de devolução do Full que a consulta por envio não acha (vendas mais
# antigas), pelo download em lote de documentos fiscais do ML, mês a mês (Ml::ReturnInvoiceArchive). Meses passados já
# lidos ficam em ml_accounts.return_invoice_months e não são pedidos de novo; o mês corrente é relido todo dia.
module Ml
  class ReturnInvoicesArchiveJob < ApplicationJob
    limits_concurrency to: 1, key: ->(account_id = nil) { "return-invoices-archive-#{account_id}" }, duration: 2.hours, on_conflict: :discard

    def perform(account_id = nil)
      return MlAccount.active.find_each { |a| self.class.perform_later(a.id) } if account_id.nil?

      account = MlAccount.find_by(id: account_id)
      self.class.run(account) if account
    end

    def self.run(account, sleeper: ->(s) { sleep(s) })
      pending = pending_full(account)
      return { months: [], found: 0 } if pending.empty?

      Ml::OAuth.refresh!(account)
      done = Array(account.return_invoice_months)
      months = Ml::ReturnInvoiceArchive.months_for(account, pending, done)
      current = ActiveSupport::TimeZone["America/Sao_Paulo"].today.beginning_of_month
      found = 0
      months.each do |m|
        map = Ml::ReturnInvoiceArchive.month(account, m, sleeper: sleeper)
        pending.each do |claim|
          inv = map[claim.order_id.to_i]
          next unless inv && claim.return_invoice.nil?

          claim.update_columns(return_invoice: inv, return_invoice_checked_at: Time.current)
          found += 1
        end
        done |= [ m.strftime("%Y-%m") ] if m < current
        account.update_columns(return_invoice_months: done)
      rescue Ml::Client::Error, JSON::ParserError, ArgumentError, Faraday::Error => e
        Rails.logger.warn("[notas de devolução em lote] #{account.id} #{m}: #{e.message}")
      end
      { months: months.map { |m| m.strftime("%Y-%m") }, found: found }
    end

    # Devoluções efetivadas de vendas Full (no Lunna) ainda sem nota.
    def self.pending_full(account)
      claims = account.ml_claims.where("devolution->>'status' = ?", "delivered").where(return_invoice: nil).where.not(order_id: nil).to_a
      full = account.ml_orders.where(order_id: claims.map(&:order_id)).where("shipment->>'logistic_type' = ?", "fulfillment").pluck(:order_id).to_set
      claims.select { |c| full.include?(c.order_id) }
    end
  end
end
