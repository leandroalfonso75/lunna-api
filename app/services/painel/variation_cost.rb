# Custo de um anúncio com variações quando o SKU do anúncio (ex.: "MONDSC13-DIF") não existe no Olist nem no custo
# manual: usa os SKUs das variações que o anúncio vendeu nos últimos 90 dias (as linhas de pedido trazem o SKU da
# variação, ex.: LS-SC13-DIF-110 e LS-SC13-DIF-220), com o custo de cada um pelo Olist (kit = soma dos componentes) ou
# manual, em média ponderada pelas unidades vendidas. Variação sem custo fica de fora da média; sem nenhuma, sem custo.
module Painel
  module VariationCost
    DAYS = 90
    Result = Struct.new(:value, :source, :skus, keyword_init: true)

    module_function

    # => { item_id => Result } só para os anúncios em que achou custo pelas variações.
    def for_items(account, item_ids)
      item_ids = item_ids.compact_blank.uniq
      return {} if item_ids.empty?

      sold = MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
        .where(o: { ml_account_id: account.id }).where.not(o: { status: %w[cancelled invalid] })
        .where(item_id: item_ids).where("o.date_created >= ?", DAYS.days.ago).where.not(sku: [ nil, "" ])
        .group("ml_order_items.item_id", "ml_order_items.sku").sum("ml_order_items.quantity")
      return {} if sold.empty?

      skus = sold.keys.map(&:last).uniq
      company = account.company
      olist = Olist::UnitCost.for_skus(company, skus)
      manual = company.ml_costs.where(sku: skus).index_by(&:sku)
      cost_of = ->(sku) { olist[sku]&.value&.to_f || (manual[sku] && manual[sku].cost.to_f + manual[sku].extra.to_f) }

      sold.group_by { |(item_id, _), _| item_id }.each_with_object({}) do |(item_id, rows), out|
        known = rows.filter_map { |(_, sku), qty| (c = cost_of.call(sku)) && [ sku, c, qty.to_i ] }
        units = known.sum { |_, _, q| q }
        next if units.zero?

        out[item_id] = Result.new(value: (known.sum { |_, c, q| c * q } / units).round(2), source: "variacoes", skus: known.map(&:first))
      end
    end
  end
end
