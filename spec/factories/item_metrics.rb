FactoryBot.define do
  factory :item_metric do
    ml_account
    sequence(:item_id) { |n| "MLB#{1_000_000_000 + n}" }
    title { "Anúncio de teste" }
    status { "active" }
    sku { nil }
    listing_type { "P" }
    full { false }
    free_shipping { false }
    catalog { false }
    variations { 1 }
    price { 99.9 }
    original_price { nil }
    stock { 10 }
    quality_score { 80 }

    visits_7d { 0 }
    prev_visits_7d { 0 }
    visits_30d { 0 }
    prev_visits_30d { 0 }

    units_today { 0 }
    units_7d { 0 }
    prev_units_7d { 0 }
    units_30d { 0 }
    prev_units_30d { 0 }

    revenue_7d { 0 }
    prev_revenue_7d { 0 }
    revenue_30d { 0 }
    prev_revenue_30d { 0 }

    net_after_fee_7d { 0 }
    fees_30d { 0 }

    conversion_7d { nil }
    prev_conversion_7d { nil }
    conversion_30d { nil }
    prev_conversion_30d { nil }

    units_delta { nil }
    coverage_days { nil }
    coverage_30d { nil }

    computed_at { Time.current }
  end
end
