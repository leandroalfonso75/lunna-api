FactoryBot.define do
  factory :ml_item do
    ml_account
    sequence(:item_id) { |n| "MLB#{1_000_000_000 + n}" }
    seller_id { ml_account.seller_id }
    title { "Anúncio de teste" }
    status { "active" }
    price { 99.9 }
    available_quantity { 10 }
    sold_quantity { 0 }
    listing_type_id { "gold_pro" }
    category_id { "MLB1234" }
    free_shipping { false }
    attrs_filled { [] }
  end
end
