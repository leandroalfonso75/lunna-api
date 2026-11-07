# Regras da ficha técnica usadas na Curva ABC (sugestões e "Alterar ficha técnica AGORA").
module Ml
  module SpecRules
    # Números de documentos regulatórios (Anvisa, CONAMA, AFE, INMETRO...): o ML não exige e não mexem na qualidade do
    # anúncio; fora das sugestões quando não são obrigatórios (pedido do usuário em 07/11/2026).
    REGULATORY = /ANVISA|CONAMA|\AAFE_|INMETRO|DOCUMENT_NUMBER|LICENSE_NUMBER|CERTIFICATION_NUMBER|CERTIFICATE_NUMBER|REGISTRATION_NUMBER/

    # "Não se aplica" no ML = value_id "-1" (value_name nulo).
    NOT_APPLICABLE = "-1"

    def self.tags(a) = a["tags"] || {}
    def self.required?(a) = !!(tags(a)["required"] || tags(a)["catalog_required"])

    def self.excluded?(a)
      t = tags(a)
      return true if a["id"] == "SELLER_SKU" || t["read_only"] || t["hidden"] || t["fixed"]

      !required?(a) && a["id"].to_s.match?(REGULATORY)
    end

    # O ML mostra "Não se aplica" nos campos que não são obrigatórios.
    def self.allows_not_applicable?(a) = !required?(a)
  end
end
