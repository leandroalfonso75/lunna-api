FactoryBot.define do
  factory :olist_product do
    company
    sequence(:olist_id) { |n| 339_000_000 + n }
    sequence(:sku) { |n| "SKU-#{n}" }
    sequence(:description) { |n| "Produto de teste #{n}" }
    kind { "S" }
    status { "A" }
    variation_kind { "N" }
    price { 100 }
    promo_price { 0 }
    cost_price { 40 }
    avg_cost_price { 38.5 }
    stock_balance { 10 }
    stock_reserved { 2 }
    stock_available { 8 }
    synced_at { Time.current }
  end

  factory :olist_sync_run do
    company
    trigger { "auto" }
    status { "running" }
    started_at { Time.current }
  end

  factory :olist_change do
    company
    user { association :user, company: company }
    olist_product_id { 339_000_001 }
    kind { "price" }
    status { "done" }
  end
end
