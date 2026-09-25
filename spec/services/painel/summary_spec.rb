require "rails_helper"

RSpec.describe Painel::Summary do
  let(:account) { create(:ml_account) }

  it "agrupa closed e inactive em closed" do
    create(:ml_item, ml_account: account, item_id: "MLB1", status: "active")
    create(:ml_item, ml_account: account, item_id: "MLB2", status: "paused")
    create(:ml_item, ml_account: account, item_id: "MLB3", status: "closed")
    create(:ml_item, ml_account: account, item_id: "MLB4", status: "inactive")
    create(:ml_item, ml_account: account, item_id: "MLB5", status: "under_review")

    expect(described_class.call(account)).to eq(total: 5, active: 1, paused: 1, closed: 2, under_review: 1)
  end

  it "não conta anúncios de outra conta" do
    create(:ml_item, ml_account: account, item_id: "MLB1", status: "active")
    create(:ml_item, status: "active") # outra conta

    expect(described_class.call(account)[:total]).to eq(1)
  end
end
