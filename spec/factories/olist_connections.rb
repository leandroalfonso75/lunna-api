FactoryBot.define do
  factory :olist_connection do
    company
    access_token { "olist-access-token" }
    refresh_token { "olist-refresh-token" }
    expires_at { 3.hours.from_now }
    refresh_expires_at { 20.hours.from_now }
    status { "active" }
  end
end
