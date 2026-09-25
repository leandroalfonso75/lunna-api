require "rails_helper"

RSpec.describe CleanupJob do
  it "apaga states de OAuth expirados, sessões vencidas e ml_sync_runs com mais de 30 dias" do
    company = create(:company)
    user = create(:user, company: company)
    old_state = create(:ml_oauth_state, company: company, user: user, created_at: 2.hours.ago)
    fresh_state = create(:ml_oauth_state, company: company, user: user, created_at: 10.minutes.ago)

    old_session = Session.create!(user: user, token_digest: "d1", expires_at: 1.hour.ago, ip: "127.0.0.1")
    fresh_session = Session.create!(user: user, token_digest: "d2", expires_at: 1.hour.from_now, ip: "127.0.0.1")

    account = create(:ml_account, company: company)
    old_run = create(:ml_sync_run, ml_account: account, started_at: 31.days.ago, finished_at: 31.days.ago)
    recent_run = create(:ml_sync_run, ml_account: account, started_at: 29.days.ago, finished_at: 29.days.ago)

    described_class.perform_now

    expect(MlOauthState.exists?(old_state.state)).to be false
    expect(MlOauthState.exists?(fresh_state.state)).to be true
    expect(Session.exists?(old_session.id)).to be false
    expect(Session.exists?(fresh_session.id)).to be true
    expect(MlSyncRun.exists?(old_run.id)).to be false
    expect(MlSyncRun.exists?(recent_run.id)).to be true
  end
end
