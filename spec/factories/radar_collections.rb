FactoryBot.define do
  factory :radar_collection do
    company
    sequence(:category_path) { |n| "Pet Shop > Categoria #{n}" }
    status { "requested" }
  end
end
