FactoryBot.define do
  factory :radar_search do
    company
    user { association :user, company: company }
    sequence(:category_path) { |n| "Beleza e Cuidado Pessoal > Categoria #{n}" }
    filters { { "category" => category_path, "period" => 30 } }
    data_ref { Date.new(2026, 9, 23) }
    total_items { 10 }
    total_sold { 500 }
    total_revenue { 12_345.5 }
    median_price { 49.9 }
  end
end
