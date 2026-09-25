require "rails_helper"

RSpec.describe Ml::SyncAllJob do
  it "enfileira Ml::SyncJob só para as contas active, pulando reauth_required" do
    active = create(:ml_account, status: "active")
    create(:ml_account, status: "reauth_required")

    expect { described_class.perform_now }.to have_enqueued_job(Ml::SyncJob).with(active.id).exactly(1).times
  end
end
