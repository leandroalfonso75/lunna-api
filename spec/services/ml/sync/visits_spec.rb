require "rails_helper"

RSpec.describe Ml::Sync::Visits do
  let(:account) { create(:ml_account, seller_id: 430_014_725) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }

  it "upserta um dia por item (10 primeiros caracteres da data), visits = total" do
    stub_request(:get, "https://api.mercadolibre.com/items/MLB1000000001/visits/time_window")
      .with(query: { last: "60", unit: "day" })
      .to_return(status: 200, body: ml_fixture("visits_time_window"))

    result = described_class.call(client, account, [ "MLB1000000001" ])

    expect(result.notes).to eq([])
    rows = MlItemVisit.where(item_id: "MLB1000000001").order(:day)
    expect(rows.map { |r| r.day.iso8601 }).to eq(%w[2026-09-20 2026-09-21 2026-09-22 2026-09-23 2026-09-24])
    expect(rows.find { |r| r.day.iso8601 == "2026-09-20" }.visits).to eq(30)
    expect(rows.first.ml_account_id).to eq(account.id)
  end

  it "erro num item vira nota e não impede os outros de serem gravados" do
    stub_request(:get, "https://api.mercadolibre.com/items/MLB1/visits/time_window")
      .with(query: { last: "60", unit: "day" })
      .to_return(status: 500, body: "erro")
    stub_request(:get, "https://api.mercadolibre.com/items/MLB2/visits/time_window")
      .with(query: { last: "60", unit: "day" })
      .to_return(status: 200, body: ml_fixture("visits_time_window"))

    result = described_class.call(client, account, %w[MLB1 MLB2])

    expect(result.notes.first).to include("MLB1")
    expect(MlItemVisit.where(item_id: "MLB2").count).to eq(5)
    expect(MlItemVisit.where(item_id: "MLB1").count).to eq(0)
  end
end
