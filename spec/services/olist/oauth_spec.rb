require "rails_helper"

RSpec.describe Olist::OAuth do
  let(:token_url) { "https://accounts.tiny.com.br/realms/tiny/protocol/openid-connect/token" }

  before do
    stub_env(
      "OLIST_CLIENT_ID" => "client-olist",
      "OLIST_CLIENT_SECRET" => "secret-olist",
      "API_URL" => "https://api.lunna.test"
    )
  end

  describe ".configured?" do
    it "exige client id e secret" do
      expect(described_class.configured?).to be true
      stub_env("OLIST_CLIENT_SECRET" => nil)
      expect(described_class.configured?).to be false
    end
  end

  describe ".authorize_url" do
    it "monta a URL do Olist com client_id, redirect_uri, scope openid e state" do
      uri = URI.parse(described_class.authorize_url("state-1"))
      query = URI.decode_www_form(uri.query).to_h

      expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("https://accounts.tiny.com.br/realms/tiny/protocol/openid-connect/auth")
      expect(query).to include(
        "client_id" => "client-olist",
        "redirect_uri" => "https://api.lunna.test/auth/olist/callback",
        "scope" => "openid",
        "response_type" => "code",
        "state" => "state-1"
      )
    end
  end

  describe ".exchange_code" do
    it "troca o code pelos tokens" do
      stub = stub_request(:post, token_url)
        .with(body: hash_including("grant_type" => "authorization_code", "code" => "abc", "client_id" => "client-olist",
          "client_secret" => "secret-olist", "redirect_uri" => "https://api.lunna.test/auth/olist/callback"))
        .to_return(status: 200, body: { access_token: "A", refresh_token: "R", expires_in: 14_400 }.to_json)

      expect(described_class.exchange_code("abc")).to include("access_token" => "A", "refresh_token" => "R")
      expect(stub).to have_been_requested
    end

    it "levanta Error quando o Olist recusa" do
      stub_request(:post, token_url).to_return(status: 400, body: "{}")

      expect { described_class.exchange_code("ruim") }.to raise_error(described_class::Error, /status 400/)
    end
  end

  describe ".refresh!" do
    let(:connection) { create(:olist_connection, expires_at: 1.minute.from_now) }

    it "renova perto de expirar e grava o refresh_token novo" do
      stub_request(:post, token_url)
        .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "olist-refresh-token"))
        .to_return(status: 200, body: { access_token: "A2", refresh_token: "R2", expires_in: 14_400, refresh_expires_in: 86_400 }.to_json)

      described_class.refresh!(connection)

      connection.reload
      expect(connection.access_token).to eq("A2")
      expect(connection.refresh_token).to eq("R2")
      expect(connection.expires_at).to be > 3.hours.from_now
      expect(connection.status).to eq("active")
    end

    it "mantém o refresh_token quando a resposta não traz um novo" do
      stub_request(:post, token_url).to_return(status: 200, body: { access_token: "A3", expires_in: 14_400 }.to_json)

      described_class.refresh!(connection)

      expect(connection.reload.refresh_token).to eq("olist-refresh-token")
    end

    it "não chama o Olist se o acesso ainda vale" do
      fresh = create(:olist_connection, expires_at: 2.hours.from_now)

      described_class.refresh!(fresh)

      expect(WebMock).not_to have_requested(:post, token_url)
    end

    it "marca reauth_required e levanta erro se a renovação falhar" do
      stub_request(:post, token_url).to_return(status: 400, body: "{}")

      expect { described_class.refresh!(connection) }.to raise_error(described_class::Error)

      expect(connection.reload.status).to eq("reauth_required")
      expect(connection.last_error).to be_present
    end
  end
end
