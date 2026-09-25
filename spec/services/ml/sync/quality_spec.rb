require "rails_helper"

RSpec.describe Ml::Sync::Quality do
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let!(:item) { create(:ml_item, item_id: "MLB1000000001") }

  it "grava quality_score, quality_level (level_wording) e só as regras PENDING em quality_pending" do
    stub_request(:get, "https://api.mercadolibre.com/item/MLB1000000001/performance")
      .to_return(status: 200, body: ml_fixture("item_performance"))

    result = described_class.call(client, [ "MLB1000000001" ])

    expect(result.notes).to eq([])
    item.reload
    expect(item.quality_score).to eq(65)
    expect(item.quality_level).to eq("Padrão")
    expect(item.quality_pending.map { |r| r["key"] }).to eq(%w[COMPLETE_GTIN OFFER_INSTALLMENTS])
    expect(item.quality_pending.first).to include("area" => "Ficha técnica", "label" => "Completar ficha técnica", "mode" => "OPPORTUNITY")
    expect(item.quality_checked_at).to be_present
  end

  it "usa level quando não tem level_wording" do
    body = JSON.parse(ml_fixture("item_performance"))
    body["level_wording"] = nil
    stub_request(:get, "https://api.mercadolibre.com/item/MLB1000000001/performance")
      .to_return(status: 200, body: body.to_json)

    described_class.call(client, [ "MLB1000000001" ])

    expect(item.reload.quality_level).to eq("Standard")
  end

  it "carimba quality_checked_at mesmo com erro, e vira nota" do
    stub_request(:get, "https://api.mercadolibre.com/item/MLB1000000001/performance")
      .to_return(status: 500, body: "erro")

    result = described_class.call(client, [ "MLB1000000001" ])

    expect(result.notes.first).to include("MLB1000000001")
    item.reload
    expect(item.quality_checked_at).to be_present
    expect(item.quality_score).to be_nil
  end
end
