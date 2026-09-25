require "rails_helper"

RSpec.describe Ml::Sync::Scan do
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }

  def stub_scan(scroll_id:, fixture:)
    query = { search_type: "scan", limit: "100" }
    query[:scroll_id] = scroll_id if scroll_id

    stub_request(:get, "https://api.mercadolibre.com/users/430014725/items/search")
      .with(query: query)
      .to_return(status: 200, body: ml_fixture(fixture))
  end

  it "pagina com scroll_id e para na primeira página vazia" do
    stub_scan(scroll_id: nil, fixture: "items_search_scan_1")
    stub_scan(scroll_id: "scroll-1", fixture: "items_search_scan_2")
    stub_scan(scroll_id: "scroll-2", fixture: "items_search_scan_3")

    result = described_class.call(client, 430_014_725)

    expect(result.ids).to eq(%w[MLB1000000001 MLB1000000002 MLB1000000003 MLB1000000004 MLB1000000005])
    expect(result.notes).to eq([])
  end

  it "para no limite de 100 páginas mesmo se a página nunca vier vazia" do
    stub_request(:get, "https://api.mercadolibre.com/users/430014725/items/search")
      .with(query: hash_including(search_type: "scan", limit: "100"))
      .to_return(status: 200, body: { results: [ "MLB1" ], scroll_id: "sempre-mais" }.to_json)

    result = described_class.call(client, 430_014_725)

    expect(result.ids.size).to eq(100)
    expect(WebMock).to have_requested(:get, %r{\Ahttps://api\.mercadolibre\.com/users/430014725/items/search}).times(100)
  end

  it "erro numa página vira nota e devolve o que já tinha coletado" do
    stub_scan(scroll_id: nil, fixture: "items_search_scan_1")
    stub_request(:get, "https://api.mercadolibre.com/users/430014725/items/search")
      .with(query: { search_type: "scan", limit: "100", scroll_id: "scroll-1" })
      .to_return(status: 500, body: "erro")

    result = described_class.call(client, 430_014_725)

    expect(result.ids).to eq(%w[MLB1000000001 MLB1000000002 MLB1000000003])
    expect(result.notes.first).to include("scan")
  end
end
