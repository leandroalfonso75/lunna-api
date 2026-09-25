FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Empresa #{n}" }

    trait :with_ai do
      openrouter_api_key { "sk-or-v1-fake-key-1234" }
      ai_model { "anthropic/claude-sonnet-4.5" }
    end
  end
end
