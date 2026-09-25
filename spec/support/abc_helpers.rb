# Doubles pros specs dos serviços puros de Abc:: (Classifier, Economics,
# PriceSuggestion, SuggestionEngine) — evita precisar de banco/factories pra
# testar regra de negócio. `build_metric` imita uma linha de `item_metrics`
# (A4), `build_item` imita um `ml_item` (A3); `price_ref`/`quality_pending`
# usam chaves STRING, igual ao jsonb lido do banco de verdade.
module AbcHelpers
  MetricDouble = Struct.new(
    :item_id, :status, :title, :sku, :full, :free_shipping, :listing_type,
    :price, :stock, :quality_score,
    :visits_30d, :prev_visits_30d, :units_30d, :prev_units_30d,
    :revenue_30d, :prev_revenue_30d, :fees_30d,
    :conversion_30d, :prev_conversion_30d, :coverage_30d,
    keyword_init: true
  )

  ItemDouble = Struct.new(
    :item_id, :brand, :model, :listing_type_id, :free_shipping, :has_video,
    :pictures_count, :description_len, :quality_score, :quality_pending,
    :attrs_missing_required, :attrs_missing_main, :price, :fee_now, :ship_cost,
    :price_ref, :fee_at_ref, :ship_at_ref, :details_checked_at,
    keyword_init: true
  )

  def build_metric(**attrs)
    MetricDouble.new(**{
      item_id: "MLB1", status: "active", title: "Furadeira de Impacto Profissional Industrial 750W", sku: "SKU1",
      full: false, free_shipping: false, listing_type: "P",
      price: 100.0, stock: 10, quality_score: 80,
      visits_30d: 0, prev_visits_30d: 0, units_30d: 0, prev_units_30d: 0,
      revenue_30d: 0, prev_revenue_30d: 0, fees_30d: 0,
      conversion_30d: nil, prev_conversion_30d: nil, coverage_30d: nil
    }.merge(attrs))
  end

  def build_item(**attrs)
    ItemDouble.new(**{
      item_id: "MLB1", brand: nil, model: nil, listing_type_id: "gold_pro", free_shipping: false,
      has_video: true, pictures_count: 8, description_len: 500, quality_score: 80,
      quality_pending: [], attrs_missing_required: [], attrs_missing_main: [],
      price: 100.0, fee_now: 10.0, ship_cost: 5.0,
      price_ref: nil, fee_at_ref: nil, ship_at_ref: nil, details_checked_at: Time.current
    }.merge(attrs))
  end

  def abc_params(**attrs)
    Abc::Params.new(**{
      tax_pct: 11.3, min_margin_pct: 9.0, cut_a: 80.0, cut_b: 95.0, up_pct: 10.0, down_pct: -15.0
    }.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include AbcHelpers
end
