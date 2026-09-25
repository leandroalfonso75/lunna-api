# SPEC 8.4 — lucro/sobra e margem por unidade e no mês. `metric` é a linha de
# `item_metrics` (preço de venda, vendas/faturamento/tarifas 30d); `item` é o
# `ml_item` correspondente (fee_now, ship_cost, preço cheio); `cost` é o custo
# por unidade já resolvido (cost + extra do SKU) ou nil quando o anúncio não
# tem custo cadastrado. Serviço puro: nenhuma consulta ao banco aqui.
module Abc
  class Economics
    Result = Struct.new(:unit, :month, keyword_init: true)

    def self.call(metric:, item:, cost:, params:) = new(metric, item, cost, params).call

    def initialize(metric, item, cost, params)
      @metric = metric
      @item = item
      @cost = cost
      @params = params
    end

    def call
      Result.new(unit: unit_economics, month: month_economics)
    end

    private

    def has_cost? = !@cost.nil?

    def price = @metric.price.to_f

    def units_30d = @metric.units_30d.to_i

    # fee_now do ml_item; sem ele, tarifas reais 30d ÷ vendas 30d (0 se não
    # vendeu — não dá pra estimar tarifa unitária sem nenhuma venda).
    def fee_per_unit
      fee_now = @item&.fee_now
      return fee_now.to_f if fee_now.present?

      units_30d.zero? ? 0.0 : @metric.fees_30d.to_f / units_30d
    end

    def shipping_per_unit
      ship_cost = @item&.ship_cost
      ship_cost.present? ? ship_cost.to_f : 0.0
    end

    def tax_per_unit = price * @params.tax_pct / 100.0

    # Preço cheio só quando há desconto de verdade (o front mostra "de R$ x" sem decidir nada).
    def full_price
      full = @item&.price&.to_f
      full if full && full > price
    end

    def unit_economics
      sobra = price - fee_per_unit - shipping_per_unit - tax_per_unit
      profit = has_cost? ? sobra - @cost.to_f : sobra
      margin_pct = price.positive? ? (profit / price * 100) : nil

      {
        price: price,
        full_price: full_price,
        fee: fee_per_unit,
        shipping: shipping_per_unit,
        tax: tax_per_unit,
        cost: has_cost? ? @cost.to_f : nil,
        profit: profit,
        margin_pct: margin_pct,
        margin_state: margin_state(margin_pct, profit),
        profit_state: profit_state(profit),
        profit_is_before_cost: !has_cost?,
        low_margin: low_margin?(margin_pct)
      }
    end

    def month_economics
      revenue = @metric.revenue_30d.to_f
      fees = @metric.fees_30d.to_f
      fees = fee_per_unit * units_30d if fees.zero?
      shipping = shipping_per_unit * units_30d
      tax = revenue * @params.tax_pct / 100.0
      cost_total = has_cost? ? @cost.to_f * units_30d : nil
      profit = revenue - fees - shipping - tax - cost_total.to_f
      margin_pct = revenue.zero? ? nil : (profit / revenue * 100)

      {
        revenue: revenue,
        fees: fees,
        shipping: shipping,
        tax: tax,
        cost: cost_total,
        profit: profit,
        margin_pct: margin_pct,
        margin_state: margin_state(margin_pct, profit),
        profit_state: profit_state(profit),
        profit_is_before_cost: !has_cost?,
        low_margin: low_margin?(margin_pct)
      }
    end

    # Sem custo cadastrado não dá pra avaliar margem mínima (SPEC 8.4).
    def margin_state(margin_pct, profit)
      return nil unless has_cost?

      ((margin_pct && margin_pct < @params.min_margin_pct) || profit.negative?) ? "bad" : "ok"
    end

    def profit_state(profit) = profit.negative? ? "bad" : "ok"

    def low_margin?(margin_pct)
      return false unless has_cost?

      margin_pct.present? && margin_pct < @params.min_margin_pct
    end
  end
end
