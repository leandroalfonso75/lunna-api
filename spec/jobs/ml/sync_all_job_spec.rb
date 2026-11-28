require "rails_helper"

RSpec.describe Ml::SyncAllJob do
  it "enfileira Ml::SyncJob para as contas active; reauth_required só se a tentativa automática renovar o acesso" do
    active = create(:ml_account, status: "active")
    create(:ml_account, status: "reauth_required", auth_retry_count: Ml::OAuth::AUTO_RETRIES) # já esgotou as tentativas

    expect { described_class.perform_now }.to have_enqueued_job(Ml::SyncJob).with(active.id).exactly(1).times
  end

  it "conta marcada cujo token ainda vale volta a sincronizar sozinha (28/11/2026)" do
    marked = create(:ml_account, status: "reauth_required", refresh_token: "TG-old", expires_at: 1.hour.ago)
    stub_request(:post, "https://api.mercadolibre.com/oauth/token").to_return(status: 200, body: ml_fixture("oauth_refresh"))

    expect { described_class.perform_now }.to have_enqueued_job(Ml::SyncJob).with(marked.id).at_least(1).times
    expect(marked.reload.status).to eq("active")
  end

  it "conta marcada que o ML continua recusando fica parada e conta a tentativa" do
    marked = create(:ml_account, status: "reauth_required", refresh_token: "TG-old")
    stub_request(:post, "https://api.mercadolibre.com/oauth/token").to_return(status: 400, body: ml_fixture("error_invalid_grant"))

    expect { described_class.perform_now }.not_to have_enqueued_job(Ml::SyncJob).with(marked.id)
    expect(marked.reload).to have_attributes(status: "reauth_required", auth_retry_count: 1)
  end
end
