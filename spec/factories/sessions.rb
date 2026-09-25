FactoryBot.define do
  factory :session do
    user
    token_digest { Session.digest(SecureRandom.urlsafe_base64(32)) }
    expires_at { 30.days.from_now }
    ip { "127.0.0.1" }
    user_agent { "rspec" }
  end
end
