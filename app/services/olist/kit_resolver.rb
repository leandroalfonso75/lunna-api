# Custo e estoque de um KIT do Olist a partir dos produtos que o compõem.
#
# - Custo do kit = soma de (quantidade × custo unitário) de cada componente. O custo de cada
#   componente segue a mesma ordem de Olist::UnitCost (PEPS → cadastro → médio). Se algum componente
#   não tem custo, o custo do kit fica vazio (não vale subestimar) e os SKUs sem custo são listados.
# - Estoque disponível do kit = quantos kits fechados os componentes permitem montar:
#   o menor valor de ⌊disponível do componente ÷ quantidade no kit⌋.
module Olist
  class KitResolver
    Result = Struct.new(:components, :unit_cost, :missing_cost, :available, :complete, keyword_init: true)

    # => { kit olist_id => Result } só para kits com composição conhecida.
    def self.for_kits(company, kits)
      new(company, kits).call
    end

    def initialize(company, kits)
      @company = company
      @kits = kits.select { |kit| kit.kind == "K" && kit.kit_components.present? }
    end

    def call
      return {} if @kits.empty?

      ids = @kits.flat_map { |kit| kit.kit_components.map { |component| component["id"] } }.uniq
      products = OlistProduct.where(company_id: @company.id, olist_id: ids).index_by(&:olist_id)

      @kits.to_h { |kit| [ kit.olist_id, resolve(kit, products) ] }
    end

    private

    def resolve(kit, products)
      rows = kit.kit_components.map { |component| component_row(component, products[component["id"]]) }
      missing = rows.select { |row| row[:unit_cost].nil? }.map { |row| row[:sku] }
      complete = rows.none? { |row| row[:product_missing] }
      possible = rows.map { |row| row[:kits_possible] }

      Result.new(
        components: rows.map { |row| row.except(:product_missing) },
        unit_cost: missing.empty? ? rows.sum { |row| row[:subtotal] } : nil,
        missing_cost: missing,
        available: complete && possible.none?(&:nil?) ? possible.min : nil,
        complete: complete
      )
    end

    def component_row(component, product)
      quantity = component["quantity"].to_f
      cost = product && Olist::UnitCost.cost_of(product)
      available = product&.stock_available&.to_f

      {
        id: component["id"], sku: component["sku"] || product&.sku, description: product&.description,
        quantity: quantity, unit_cost: cost&.value&.to_f, cost_source: cost&.source,
        subtotal: cost ? cost.value.to_f * quantity : nil,
        available: available, kits_possible: available && quantity.positive? ? (available / quantity).floor : nil,
        product_missing: product.nil?
      }
    end
  end
end
