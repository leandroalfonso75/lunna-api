require "rails_helper"

RSpec.describe Ml::Sync::Items do
  let(:account) { create(:ml_account, seller_id: 430_014_725) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let(:ids) { JSON.parse(ml_fixture("items_multiget")).map { |e| e.dig("body", "id") }.compact + [ "MLB1000000099" ] }

  it "sobe os itens com code 200 em ml_items; code != 200 vira nota" do
    stub_request(:get, "https://api.mercadolibre.com/items")
      .with(query: hash_including(ids: ids.join(",")))
      .to_return(status: 200, body: ml_fixture("items_multiget"))

    result = described_class.call(client, account, ids)

    expect(result.ids).to match_array(ids - [ "MLB1000000099" ])
    expect(result.notes.size).to eq(1)
    expect(result.notes.first).to include("MLB1000000099").and include("404")
    expect(MlItem.where(ml_account: account).count).to eq(5)
    expect(MlItem.find("MLB1000000001").title).to include("Luminária")
  end

  it "divide em lotes de 20 ids por chamada de multiget" do
    many_ids = (1..25).map { |n| "MLB#{n}" }

    stub_request(:get, "https://api.mercadolibre.com/items")
      .with(query: hash_including(ids: many_ids.first(20).join(",")))
      .to_return(status: 200, body: "[]")
    stub_request(:get, "https://api.mercadolibre.com/items")
      .with(query: hash_including(ids: many_ids.last(5).join(",")))
      .to_return(status: 200, body: "[]")

    described_class.call(client, account, many_ids)

    expect(WebMock).to have_requested(:get, %r{\Ahttps://api\.mercadolibre\.com/items\?}).twice
  end

  it "erro num lote vira nota e os outros lotes seguem" do
    many_ids = (1..25).map { |n| "MLB#{n}" }

    stub_request(:get, "https://api.mercadolibre.com/items")
      .with(query: hash_including(ids: many_ids.first(20).join(",")))
      .to_return(status: 500, body: "erro")
    stub_request(:get, "https://api.mercadolibre.com/items")
      .with(query: hash_including(ids: many_ids.last(5).join(",")))
      .to_return(status: 200, body: "[]")

    result = described_class.call(client, account, many_ids)

    expect(result.notes.first).to include("multiget")
    # 1º lote: 500 tenta 3 vezes (retentativa do Ml::Client); 2º lote: 1 chamada.
    expect(WebMock).to have_requested(:get, %r{\Ahttps://api\.mercadolibre\.com/items\?}).times(4)
  end

  it "upsert_all atualiza um item já existente sem duplicar" do
    create(:ml_item, ml_account: account, item_id: "MLB1000000001", title: "título antigo")

    stub_request(:get, "https://api.mercadolibre.com/items")
      .with(query: hash_including(ids: ids.join(",")))
      .to_return(status: 200, body: ml_fixture("items_multiget"))

    described_class.call(client, account, ids)

    expect(MlItem.where(item_id: "MLB1000000001").count).to eq(1)
    expect(MlItem.find("MLB1000000001").title).to include("Luminária")
  end
end
