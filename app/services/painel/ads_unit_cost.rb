# Custo de Ads por unidade de cada anúncio: gasto do anúncio nos últimos N dias fechados (`companies.ads_cost_days`:
# 7, 15 ou 30) ÷ unidades vendidas dele no mesmo período (vendas não canceladas). Sem gasto, ou gasto sem venda, fica
# zero por unidade (o gasto aparece à parte). Usado em Anúncios (lucro pós Ads) e em Promoções (margem pós Ads).
module Painel
  module AdsUnitCost
    DAYS_OPTIONS = [ 7, 15, 30 ].freeze

    module_function

    # => { item_id => { spend:, units:, unit:, days: } } só para os anúncios com gasto no período.
    def for_items(account, item_ids, days: nil)
      days = (days || account.company.ads_cost_days || 15).to_i
      zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
      last = zone.today - 1
      first = last - (days - 1)
      spend = MlAdItemDaily.where(ml_account_id: account.id, item_id: item_ids, date: first..last).group(:item_id).sum(:cost)
      return {} if spend.empty?

      units = MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
        .where(o: { ml_account_id: account.id }).where.not(o: { status: %w[cancelled invalid] })
        .where(item_id: spend.keys).where("o.date_created BETWEEN ? AND ?", first.in_time_zone(zone).beginning_of_day, last.in_time_zone(zone).end_of_day)
        .group("ml_order_items.item_id").sum("ml_order_items.quantity")
      spend.to_h do |id, cost|
        sold = units[id].to_i
        [ id, { spend: cost.to_f.round(2), units: sold, unit: sold.positive? ? (cost.to_f / sold).round(2) : 0.0, days: days } ]
      end
    end
  end
end
