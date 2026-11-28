require "rails_helper"

RSpec.describe Ml::OAuth, type: :model do
  before do
    stub_env(
      "ML_CLIENT_ID" => "client-123",
      "ML_CLIENT_SECRET" => "secret-abc",
      "API_URL" => "https://api.lunna.test"
    )
  end

  describe ".configured?" do
    it "true quando ML_CLIENT_ID e ML_CLIENT_SECRET estão presentes" do
      expect(described_class.configured?).to be true
    end

    it "false faltando qualquer um dos dois" do
      stub_env("ML_CLIENT_SECRET" => nil)
      expect(described_class.configured?).to be false
    end
  end

  describe ".redirect_uri" do
    it "usa API_URL + /auth/ml/callback" do
      expect(described_class.redirect_uri).to eq("https://api.lunna.test/auth/ml/callback")
    end
  end

  describe ".authorize_url" do
    it "monta a URL de autorização com client_id, redirect_uri e state" do
      url = described_class.authorize_url("state-xyz")
      uri = URI.parse(url)
      query = URI.decode_www_form(uri.query).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

      expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("https://auth.mercadolivre.com.br/authorization")
      expect(query["response_type"]).to eq([ "code" ])
      expect(query["client_id"]).to eq([ "client-123" ])
      expect(query["redirect_uri"]).to eq([ "https://api.lunna.test/auth/ml/callback" ])
      expect(query["state"]).to eq([ "state-xyz" ])
    end
  end

  describe ".exchange_code" do
    it "troca o code por tokens (POST form-urlencoded)" do
      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .with(body: hash_including(
          "grant_type" => "authorization_code",
          "client_id" => "client-123",
          "client_secret" => "secret-abc",
          "code" => "the-code",
          "redirect_uri" => "https://api.lunna.test/auth/ml/callback"
        ))
        .to_return(status: 200, body: ml_fixture("oauth_token"), headers: { "Content-Type" => "application/json" })

      data = described_class.exchange_code("the-code")

      expect(data["access_token"]).to eq("APP_USR-access-1")
      expect(data["refresh_token"]).to eq("TG-refresh-1")
    end

    it "invalid_grant vira Ml::OAuth::Error" do
      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .to_return(status: 400, body: ml_fixture("error_invalid_grant"))

      expect { described_class.exchange_code("code-ruim") }.to raise_error(Ml::OAuth::Error)
    end
  end

  describe ".refresh!" do
    it "não chama o ML se faltar 10 min ou mais pra expirar" do
      account = create(:ml_account, expires_at: 10.minutes.from_now + 1.second, refresh_token: "TG-old")

      described_class.refresh!(account)

      expect(WebMock).not_to have_requested(:post, "https://api.mercadolibre.com/oauth/token")
      expect(account.reload.refresh_token).to eq("TG-old")
    end

    it "renova quando falta menos de 10 min (9m59s)" do
      account = create(:ml_account, expires_at: 10.minutes.from_now - 1.second, refresh_token: "TG-old")

      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "TG-old"))
        .to_return(status: 200, body: ml_fixture("oauth_refresh"))

      described_class.refresh!(account)

      expect(WebMock).to have_requested(:post, "https://api.mercadolibre.com/oauth/token").once
    end

    it "grava o novo access_token e o novo refresh_token, status active e sem last_error" do
      account = create(:ml_account,
        expires_at: 1.minute.from_now, refresh_token: "TG-old", access_token: "old-access",
        status: "reauth_required", last_error: "erro antigo")

      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .to_return(status: 200, body: ml_fixture("oauth_refresh"))

      described_class.refresh!(account)
      account.reload

      expect(account.access_token).to eq("APP_USR-access-2")
      expect(account.refresh_token).to eq("TG-refresh-2")
      expect(account.status).to eq("active")
      expect(account.last_error).to be_nil
      expect(account.expires_at).to be_within(5.seconds).of(21_600.seconds.from_now)
    end

    it "mantém o refresh_token antigo se a resposta não trouxer um novo" do
      account = create(:ml_account, expires_at: 1.minute.from_now, refresh_token: "TG-old")

      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .to_return(status: 200, body: ml_fixture("oauth_token_no_refresh"))

      described_class.refresh!(account)

      expect(account.reload.refresh_token).to eq("TG-old")
    end

    it "invalid_grant marca reauth_required, grava last_error e levanta Ml::OAuth::Error" do
      account = create(:ml_account, expires_at: 1.minute.from_now, refresh_token: "TG-old", status: "active")

      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .to_return(status: 400, body: ml_fixture("error_invalid_grant"))

      expect { described_class.refresh!(account) }.to raise_error(Ml::OAuth::Error)

      account.reload
      expect(account.status).to eq("reauth_required")
      expect(account.last_error).to eq("Falha ao renovar token do Mercado Livre. Autorize de novo.")
    end

    # 28/11/2026: em 27/11 uma falha passageira marcou a conta e parou a sincronização por 20 horas
    it "falha passageira (5xx, 429, rede) NÃO marca reauth_required: a conta segue ativa e tenta na próxima rodada" do
      account = create(:ml_account, expires_at: 1.minute.from_now, refresh_token: "TG-old", status: "active")

      [ 500, 503, 429 ].each do |code|
        stub_request(:post, "https://api.mercadolibre.com/oauth/token").to_return(status: code, body: "{}")
        expect { described_class.refresh!(account) }.to raise_error(Ml::OAuth::TransientError)
        expect(account.reload.status).to eq("active")
      end
      stub_request(:post, "https://api.mercadolibre.com/oauth/token").to_timeout
      expect { described_class.refresh!(account) }.to raise_error(Ml::OAuth::TransientError)
      expect(account.reload).to have_attributes(status: "active", refresh_token: "TG-old")
      expect(account.last_error).to include("Falha passageira")
    end

    it "invalid_grant é RevokedError (recusa de verdade)" do
      account = create(:ml_account, expires_at: 1.minute.from_now, refresh_token: "TG-old")
      stub_request(:post, "https://api.mercadolibre.com/oauth/token").to_return(status: 400, body: ml_fixture("error_invalid_grant"))

      expect { described_class.refresh!(account) }.to raise_error(Ml::OAuth::RevokedError)
    end
  end

  describe ".auto_retry!" do
    it "conta marcada tenta renovar sozinha; se o token ainda vale, volta a ficar ativa e zera as tentativas" do
      account = create(:ml_account, status: "reauth_required", refresh_token: "TG-old", expires_at: 1.hour.ago)
      stub_request(:post, "https://api.mercadolibre.com/oauth/token").to_return(status: 200, body: ml_fixture("oauth_refresh"))

      expect(described_class.auto_retry!(account)).to be true
      expect(account.reload).to have_attributes(status: "active", auth_retry_count: 0, last_error: nil, refresh_token: "TG-refresh-2")
    end

    it "no máximo 6 tentativas, uma a cada 15 minutos; depois espera o usuário autorizar" do
      account = create(:ml_account, status: "reauth_required", refresh_token: "TG-old", expires_at: 1.hour.ago)
      stub_request(:post, "https://api.mercadolibre.com/oauth/token").to_return(status: 400, body: ml_fixture("error_invalid_grant"))

      expect(described_class.auto_retry!(account)).to be false
      expect(account.reload.auth_retry_count).to eq(1)
      expect(described_class.auto_retry!(account)).to be false # menos de 15 min depois: nem tenta
      expect(account.reload.auth_retry_count).to eq(1)

      base = Time.current
      (1..6).each { |i| travel_to(base + (16 * i).minutes) { described_class.auto_retry!(account.reload) } }
      expect(account.reload.auth_retry_count).to eq(6)
      expect(WebMock).to have_requested(:post, "https://api.mercadolibre.com/oauth/token").times(6)
      expect(account.last_error).to include("Autorize de novo")
      expect(account.status).to eq("reauth_required")
    end
  end
end
