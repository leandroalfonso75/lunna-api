FactoryBot.define do
  factory :user do
    company
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Fulano" }
    password { "password123" }
    role { "member" }

    trait :admin do
      role { "admin" }
    end
  end
end
