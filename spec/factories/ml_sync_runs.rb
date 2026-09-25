FactoryBot.define do
  factory :ml_sync_run do
    ml_account
    started_at { Time.current }
  end
end
