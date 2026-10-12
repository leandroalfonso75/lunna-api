require "rails_helper"

RSpec.describe Olist::RefreshAllJob do
  let(:token_url) { "https://accounts.tiny.com.br/realms/tiny/protocol/openid-connect/token" }

  before { stub_env("OLIST_CLIENT_ID" => "c", "OLIST_CLIENT_SECRET" => "s", "API_URL" => "https://api.lunna.test") }

  it "renova todas as conexões ativas, mesmo com acesso ainda válido" do
    connection = create(:olist_connection, expires_at: 3.hours.from_now)
    stub_request(:post, token_url).to_return(status: 200, body: { access_token: "novo", refresh_token: "r2", expires_in: 14_400 }.to_json)

    described_class.perform_now

    expect(connection.reload.access_token).to eq("novo")
  end

  it "uma falha não derruba as outras e marca a conexão para reconectar" do
    bad = create(:olist_connection, refresh_token: "ruim")
    good = create(:olist_connection)
    stub_request(:post, token_url)
      .with(body: hash_including("refresh_token" => "ruim")).to_return(status: 400, body: "{}")
    stub_request(:post, token_url)
      .with(body: hash_including("refresh_token" => "olist-refresh-token"))
      .to_return(status: 200, body: { access_token: "ok", refresh_token: "r2", expires_in: 14_400 }.to_json)

    described_class.perform_now

    expect(bad.reload.status).to eq("reauth_required")
    expect(good.reload.access_token).to eq("ok")
  end

  it "ignora conexões que já pedem reconexão" do
    create(:olist_connection, status: "reauth_required")

    described_class.perform_now

    expect(WebMock).not_to have_requested(:post, token_url)
  end
end
