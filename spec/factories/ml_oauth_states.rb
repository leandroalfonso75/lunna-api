FactoryBot.define do
  factory :ml_oauth_state do
    state { SecureRandom.uuid }
    company
    user
    created_at { Time.current }
  end
end
