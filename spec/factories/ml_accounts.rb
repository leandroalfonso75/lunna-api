FactoryBot.define do
  factory :ml_account do
    company
    sequence(:seller_id) { |n| 400_000_000 + n }
    nickname { "LOJA TESTE" }
    access_token { "fake-access-token" }
    refresh_token { "fake-refresh-token" }
    expires_at { 6.hours.from_now }
    scope { "offline_access read" }
    status { "active" }
  end
end
