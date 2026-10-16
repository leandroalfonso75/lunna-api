# Custo unitário de um produto, vindo do Olist ERP (Tiny), ligado ao anúncio pelo SKU.
# Ordem: custo PEPS (entradas do Controle de Estoque) → custo cadastrado no produto →
# custo médio do produto. Sem nenhum deles, o produto fica "sem custo".
module Olist
  class UnitCost
    Result = Struct.new(:value, :source, keyword_init: true)

    # => { "SKU" => Result } só para SKUs com custo conhecido no Olist.
    def self.for_skus(company, skus)
      skus = skus.compact_blank.uniq
      return {} if skus.empty?

      products = OlistProduct.where(company_id: company.id, sku: skus).where.not(status: "E").where.not(variation_kind: "P")
        .order(Arel.sql("olist_updated_at DESC NULLS LAST"))

      products.each_with_object({}) do |product, result|
        next if result.key?(product.sku)

        cost = cost_of(product)
        result[product.sku] = cost if cost
      end
    end

    def self.cost_of(product)
      if product.fifo_unit_cost.to_f.positive?
        Result.new(value: product.fifo_unit_cost, source: "peps")
      elsif product.cost_price.to_f.positive?
        Result.new(value: product.cost_price, source: "cadastro")
      elsif product.avg_cost_price.to_f.positive?
        Result.new(value: product.avg_cost_price, source: "custo_medio")
      end
    end
    private_class_method :cost_of
  end
end
