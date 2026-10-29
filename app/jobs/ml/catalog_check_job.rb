# Confere, uma hora depois, se o anúncio de catálogo está ganhando (Painel::CatalogCheck).
module Ml
  class CatalogCheckJob < ApplicationJob
    queue_as :default

    def perform(check_id)
      check = MlCatalogCheck.find_by(id: check_id)
      Painel::CatalogCheck.call(check) if check
    end
  end
end
