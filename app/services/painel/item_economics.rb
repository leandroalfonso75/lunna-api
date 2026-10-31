# Resultado por unidade de cada anúncio da tabela de Anúncios:
#
#   Lucro líquido = preço de venda − custo − comissão − frete/taxas − despesas fixas − imposto
#
# - Custo: do Olist/Tiny pelo SKU (Olist::UnitCost); sem ele, o custo manual do SKU
#   (ml_costs: cost + extra); sem nenhum, o anúncio fica "sem custo" e o lucro não é calculado.
# - Comissão: a parte percentual da tarifa de venda prevista no anúncio (fee_now menos taxa fixa
#   e financiamento). Sem o detalhe da tarifa, a tarifa inteira entra como comissão.
# - Frete/taxas: frete que o vendedor paga (ship_cost) + taxa fixa + financiamento.
# - Despesas fixas: % do preço de venda definida na empresa (padrão 3%).
# - Imposto: % do preço de venda cadastrada em Configurações > Impostos e margem (tax_pct da empresa).
module Painel
  class ItemEconomics
    # => { item_id => economics hash } para os anúncios (metrics) da página.
    def self.for_page(account, metrics)
      new(account, metrics).call
    end

    def initialize(account, metrics)
      @account = account
      @metrics = metrics
      @company = account.company
    end

    def call
      return {} if @metrics.empty?

      items = @account.ml_items.where(item_id: @metrics.map(&:item_id)).index_by(&:item_id)
      skus = @metrics.map(&:sku).compact_blank
      olist = Olist::UnitCost.for_skus(@company, skus)
      manual = @company.ml_costs.where(sku: skus).index_by(&:sku)
      ads = AdsUnitCost.for_items(@account, @metrics.map(&:item_id))

      @metrics.to_h { |metric| [ metric.item_id, build(metric, items[metric.item_id], olist[metric.sku], manual[metric.sku], ads[metric.item_id]) ] }
    end

    private

    def build(metric, item, olist_cost, manual_cost, ads = nil)
      price = metric.price&.to_f
      return nil if price.nil? || price <= 0

      cost, source = resolve_cost(olist_cost, manual_cost)
      fees = fee_parts(item)
      fixed_pct = @company.fixed_expenses_pct.to_f
      fixed_expenses = price * fixed_pct / 100.0
      shipping_fees = fees[:shipping] + fees[:fixed_fee] + fees[:financing]
      tax_pct = @company.tax_pct.to_f
      tax = price * tax_pct / 100.0

      profit = cost.nil? ? nil : price - cost - fees[:commission] - shipping_fees - fixed_expenses - tax
      ads_unit = ads ? ads[:unit].to_f : 0.0
      after_ads = profit.nil? ? nil : profit - ads_unit

      {
        price: price,
        cost: cost, cost_source: source,
        commission: fees[:commission], shipping_fees: shipping_fees,
        shipping: fees[:shipping], fixed_fee: fees[:fixed_fee], financing: fees[:financing],
        fixed_expenses: fixed_expenses, fixed_expenses_pct: fixed_pct,
        tax: tax, tax_pct: tax_pct,
        net_profit: profit, net_profit_pct: profit.nil? ? nil : profit / price * 100.0,
        # Ads por unidade (gasto ÷ unidades vendidas nos últimos N dias fechados) e o lucro depois dele
        ads_unit: ads_unit, ads_spend: ads ? ads[:spend] : 0.0, ads_units: ads ? ads[:units] : 0, ads_days: @company.ads_cost_days,
        net_profit_after_ads: after_ads, net_profit_after_ads_pct: after_ads.nil? ? nil : after_ads / price * 100.0,
        fees_known: fees[:known], fees_split: fees[:split]
      }
    end

    def resolve_cost(olist_cost, manual_cost)
      return [ olist_cost.value.to_f, olist_cost.source ] if olist_cost
      return [ manual_cost.cost.to_f + manual_cost.extra.to_f, "manual" ] if manual_cost

      [ nil, nil ]
    end

    def fee_parts(item)
      fee_now = item&.fee_now
      shipping = item&.ship_cost.to_f
      details = item&.fee_details
      return { commission: 0.0, shipping: shipping, fixed_fee: 0.0, financing: 0.0, known: false, split: false } if fee_now.nil?

      if details.is_a?(Hash) && details.key?("fixed_fee")
        fixed = details["fixed_fee"].to_f
        financing = details["financing_add_on_fee"].to_f
        { commission: fee_now.to_f - fixed - financing, shipping: shipping, fixed_fee: fixed, financing: financing, known: true, split: true }
      else
        { commission: fee_now.to_f, shipping: shipping, fixed_fee: 0.0, financing: 0.0, known: true, split: false }
      end
    end
  end
end
