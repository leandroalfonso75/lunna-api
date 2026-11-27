# Atualiza as fichas vindas do ERP (Erp::CatalogRefresh) de todas as empresas que já migraram os produtos.
module Erp
  class CatalogRefreshJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: "erp-catalog-refresh", duration: 1.hour, on_conflict: :discard

    def perform
      Company.joins(:olist_connection).find_each do |company|
        CatalogRefresh.call(company)
      rescue StandardError => e
        Rails.logger.error("Erp::CatalogRefreshJob #{company.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
