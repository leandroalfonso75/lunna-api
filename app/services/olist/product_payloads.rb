# Monta o JSON dos produtos do Olist para a API: preços, custo, estoque do Olist,
# estoque do Full (lido do ML, ligado pelo SKU) e o total somado. Produto pai
# vem com as suas variações dentro (`variations`) e com o estoque somado delas.
module Olist
  class ProductPayloads
    def self.call(company, products)
      new(company, products).call
    end

    def initialize(company, products)
      @company = company
      @products = products
    end

    def call
      children = load_children
      everyone = @products + children.values.flatten
      full = Olist::FullStock.for_skus(@company, everyone.map(&:sku))
      @thumbnails = thumbnails_for(everyone.map(&:sku).compact_blank)
      @kits = Olist::KitResolver.for_kits(@company, everyone)

      @products.map do |product|
        node = base(product, full)
        kids = children[product.olist_id] || []
        next node.merge(variations_count: 0, variations: []) if kids.empty?

        variations = kids.map { |kid| base(kid, full) }
        node.merge(stock: aggregate(variations), cost: aggregate_cost(variations), variations_count: variations.size, variations: variations)
      end
    end

    private

    # parent_olist_id => variações (ordenadas), só dos produtos pedidos.
    def load_children
      ids = @products.map(&:olist_id)
      @company.olist_products.where(parent_olist_id: ids, variation_kind: "V")
        .order(:description, :sku, :olist_id).group_by(&:parent_olist_id)
    end

    def base(product, full)
      # Produto excluído no Olist não recebe o Full: o SKU costuma ter sido reaproveitado por outro cadastro.
      info = product.status == "E" ? nil : full[product.sku]
      {
        id: product.olist_id, parent_id: product.parent_olist_id,
        sku: product.sku, description: product.description, kind: product.kind, status: product.status,
        thumbnail: @thumbnails[product.sku],
        variation_kind: product.variation_kind, unit: product.unit, gtin: product.gtin,
        price: product.price, promo_price: product.promo_price, cost_price: product.cost_price,
        avg_cost_price: product.avg_cost_price,
        stock: stock_for(product, info),
        cost: cost_for(product, info),
        kit: kit_payload(product),
        olist_created_at: product.olist_created_at, olist_updated_at: product.olist_updated_at,
        synced_at: product.synced_at
      }
    end

    # Foto: a do anúncio do Mercado Livre com o mesmo SKU (um ativo, se houver), já que o Olist não traz imagem.
    def thumbnails_for(skus)
      return {} if skus.empty?

      MlItem.joins(:ml_account).where(ml_accounts: { company_id: @company.id }, sku: skus).where.not(thumbnail: [ nil, "" ])
        .order(Arel.sql("CASE WHEN ml_items.status = 'active' THEN 0 ELSE 1 END")).pluck(:sku, :thumbnail)
        .each_with_object({}) { |(sku, thumb), h| h[sku] ||= thumb }
    end

    # Custo PEPS (Primeiro que Entra, Primeiro que Sai) calculado das entradas do Controle de Estoque do Olist.
    # `warning`: há unidades em estoque cuja entrada não tem custo informado.
    def cost_for(product, info)
      kit = @kits[product.olist_id]
      return kit_cost(kit) if kit

      {
        available: product.fifo_calculated_at.present?,
        balance_gap: balance_gap(product, info),
        fifo_unit: product.fifo_unit_cost, stock_value: product.fifo_stock_value, units: product.fifo_units,
        warning: product.fifo_units_without_cost.to_f.positive?, warning_units: product.fifo_units_without_cost,
        shortfall: product.fifo_shortfall, layers: product.fifo_layers, calculated_at: product.fifo_calculated_at,
        registered: product.cost_price
      }
    end

    # Kit: o custo é a soma dos componentes; se algum não tem custo, fica vazio e o aviso lista quais.
    def kit_cost(kit)
      {
        available: true, balance_gap: nil,
        fifo_unit: kit.unit_cost, stock_value: nil, units: nil,
        warning: kit.missing_cost.any?, warning_units: nil, warning_skus: kit.missing_cost, shortfall: nil,
        layers: [], calculated_at: nil, registered: nil, source: "kit"
      }
    end

    def kit_available(product)
      @kits[product.olist_id]&.available
    end

    # Composição do kit (null para produto que não é kit).
    def kit_payload(product)
      kit = @kits[product.olist_id]
      return nil unless kit

      { components: kit.components, missing_cost: kit.missing_cost, complete: kit.complete }
    end

    # Diferença entre as unidades que o histórico de movimentações explica e o estoque de hoje
    # (saldo do Olist + Full do ML). Diferente de zero = o histórico não fecha com o saldo.
    def balance_gap(product, info)
      return nil if product.fifo_calculated_at.nil?

      gap = product.fifo_units.to_f - (product.stock_balance.to_f + info&.total.to_f)
      gap.abs <= 0.5 ? 0.0 : gap.round(3)
    end

    # Pai: faixa de custo das variações (menor e maior) e o aviso se alguma tiver.
    def aggregate_cost(variations)
      costs = variations.map { |variation| variation[:cost] }
      units = costs.filter_map { |cost| cost[:fifo_unit]&.to_f }

      {
        available: costs.any? { |cost| cost[:available] },
        balance_gap: nil,
        fifo_unit: nil, range: units.empty? ? nil : [ units.min, units.max ],
        stock_value: costs.filter_map { |cost| cost[:stock_value] }.sum, units: costs.filter_map { |cost| cost[:units] }.sum,
        warning: costs.any? { |cost| cost[:warning] }, warning_units: costs.filter_map { |cost| cost[:warning_units] }.sum,
        shortfall: nil, layers: [], calculated_at: costs.filter_map { |cost| cost[:calculated_at] }.min, registered: nil
      }
    end

    # Estoque total = disponível no Olist + disponível no Full (sem anúncio Full, só o do Olist).
    def stock_for(product, info)
      available = kit_available(product) || product.stock_available
      {
        balance: product.stock_balance, reserved: product.stock_reserved, available: available,
        location: product.stock_location, deposits: product.stock_deposits,
        full: full_payload(info),
        total_available: info.nil? ? available : (available || 0) + info.available
      }
    end

    def full_payload(info)
      return { linked: false, available: nil, not_available: nil, total: nil, listings: 0, synced_at: nil } if info.nil?

      { linked: true, available: info.available, not_available: info.not_available, total: info.total,
        listings: info.listings, synced_at: info.synced_at }
    end

    # Produto pai não tem estoque próprio: mostra a soma das variações.
    def aggregate(variations)
      stocks = variations.map { |variation| variation[:stock] }
      fulls = stocks.map { |stock| stock[:full] }.select { |full| full[:linked] }

      {
        balance: sum(stocks, :balance), reserved: sum(stocks, :reserved), available: sum(stocks, :available),
        location: nil, deposits: [],
        full: aggregate_full(fulls),
        total_available: sum(stocks, :total_available)
      }
    end

    def aggregate_full(fulls)
      return full_payload(nil) if fulls.empty?

      {
        linked: true, available: fulls.sum { |full| full[:available] }, not_available: fulls.sum { |full| full[:not_available] },
        total: fulls.sum { |full| full[:total] }, listings: fulls.sum { |full| full[:listings] },
        synced_at: fulls.filter_map { |full| full[:synced_at] }.min
      }
    end

    def sum(stocks, key)
      values = stocks.filter_map { |stock| stock[key] }
      values.empty? ? nil : values.sum
    end
  end
end
