FactoryBot.define do
  factory :ai_plan do
    ml_account
    sequence(:item_id) { |n| "MLB#{n}" }
    status { "pending" }
    text { "" }
  end
end
