# Estoque e custo de uma ficha vinda do ERP, lidos da cópia sincronizada (olist_products): nada é gravado.
#
# - Estoque: o disponível no depósito do ERP, pelo SKU.
# - Kit (e variação que é kit): sempre o do componente que acaba primeiro, dividindo pela quantidade usada no kit
#   (regra do usuário, 27/11/2026): A com 5 un. e B com 60 → kit com 5; se o kit usa 2 de A → 2 kits.
#   Componente que não está ativo no ERP conta como zero.
# - Custo: o PEPS do histórico de entradas (o custo cadastrado no lançamento do estoque); kit = soma dos componentes.
module Erp
  module CatalogStock
    module_function

    def call(company, product)
      skus = ([ product.sku ] + product.variations.map { |v| v["sku"] } + all_components(product).map { |c| c["sku"] }).compact.uniq
      mirror = company.olist_products.where(sku: skus, status: "A").order(:updated_at).index_by(&:sku)
      stock_of = ->(sku) { mirror[sku]&.stock_available&.to_f || 0.0 }
      cost_of = ->(sku) { m = mirror[sku]; m && (m.fifo_unit_cost || m.cost_price)&.to_f }
      # o próprio produto e as variações são lidos pelo id do ERP (há SKUs repetidos em cadastros diferentes)
      ids = ([ product.erp_id ] + product.variations.map { |v| v["erp_id"] }).compact
      by_id = ids.any? ? company.olist_products.where(olist_id: ids).index_by(&:olist_id) : {}
      own_stock = ->(erp_id, sku) { by_id[erp_id] ? by_id[erp_id].stock_available.to_f : (sku ? stock_of.(sku) : nil) }
      own_cost = ->(erp_id, sku) { (m = by_id[erp_id]) ? (m.fifo_unit_cost || m.cost_price)&.to_f : (sku ? cost_of.(sku) : nil) }

      kit = lambda do |comps|
        list = Array(comps)
        next { stock: nil, cost: nil, parts: [] } if list.empty?

        parts = list.map do |c|
          qty = c["quantity"].to_f.positive? ? c["quantity"].to_f : 1.0
          avail = stock_of.(c["sku"])
          { sku: c["sku"], name: mirror[c["sku"]]&.description, quantity: qty, available: avail, kits: (avail / qty).floor,
            cost: cost_of.(c["sku"]), found: mirror.key?(c["sku"]) }
        end
        cost = parts.all? { |x| x[:cost] } ? parts.sum { |x| x[:cost] * x[:quantity] }.round(4) : nil
        { stock: parts.map { |x| x[:kits] }.min, cost: cost, parts: parts }
      end

      own = if product.kind == "kit"
        k = kit.(product.kit_components)
        { stock: k[:stock], cost: k[:cost], parts: k[:parts] }
      elsif product.kind == "simple"
        { stock: own_stock.(product.erp_id, product.sku), cost: own_cost.(product.erp_id, product.sku), parts: [] }
      else
        { stock: nil, cost: nil, parts: [] }
      end

      variations = product.variations.to_h do |v|
        if v["kit"]
          k = kit.(product.components_for(v))
          [ v["key"], { stock: k[:stock], cost: k[:cost], parts: k[:parts], kit: true } ]
        else
          [ v["key"], { stock: own_stock.(v["erp_id"], v["sku"]), cost: own_cost.(v["erp_id"], v["sku"]), parts: [], kit: false } ]
        end
      end

      total = product.kind == "variations" ? variations.values.sum { |x| x[:stock].to_f } : own[:stock]
      { stock: own[:stock], cost: own[:cost], parts: own[:parts], variations: variations, total_stock: total }
    end

    def all_components(product)
      Array(product.kit_components) + Array(product.common_components) + product.variations.flat_map { |v| Array(v["components"]) }
    end
  end
end
