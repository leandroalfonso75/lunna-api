require "rails_helper"

RSpec.describe Session, type: :model do
  let(:user) { create(:user) }
  let(:fake_request) { Struct.new(:remote_ip, :user_agent).new("1.2.3.4", "rspec-agent") }

  describe ".start!" do
    it "grava o digest do token, não o token bruto" do
      session, token = Session.start!(user, fake_request)

      expect(session.token_digest).to eq(Digest::SHA256.hexdigest(token))
      expect(session.token_digest).not_to eq(token)
    end

    it "grava expiração em 30 dias, ip e user_agent" do
      session, = Session.start!(user, fake_request)

      expect(session.expires_at).to be_within(1.minute).of(30.days.from_now)
      expect(session.ip).to eq("1.2.3.4")
      expect(session.user_agent).to eq("rspec-agent")
    end
  end

  describe ".find_by_token" do
    it "acha a sessão pelo token bruto" do
      session, token = Session.start!(user, fake_request)

      expect(Session.find_by_token(token)).to eq(session)
    end

    it "devolve nil pra token errado" do
      Session.start!(user, fake_request)

      expect(Session.find_by_token("token-errado")).to be_nil
    end

    it "devolve nil pra token expirado" do
      _session, token = Session.start!(user, fake_request)
      Session.last.update!(expires_at: 1.second.ago)

      expect(Session.find_by_token(token)).to be_nil
    end

    it "devolve nil pra token em branco" do
      expect(Session.find_by_token(nil)).to be_nil
      expect(Session.find_by_token("")).to be_nil
    end
  end
end
