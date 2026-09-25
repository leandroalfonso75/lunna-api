# Helpers de request spec: sessão + Bearer token sem passar por POST /auth/sign_in,
# e leitura do corpo JSON.
module AuthHelpers
  FAKE_REQUEST = Struct.new(:remote_ip, :user_agent).new("127.0.0.1", "rspec").freeze
  private_constant :FAKE_REQUEST

  def auth_headers(user)
    _session, token = Session.start!(user, FAKE_REQUEST)
    { "Authorization" => "Bearer #{token}" }
  end

  def json
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
