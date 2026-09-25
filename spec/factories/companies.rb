FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Empresa #{n}" }
  end
end
