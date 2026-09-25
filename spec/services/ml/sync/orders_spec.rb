require "rails_helper"

RSpec.describe Ml::Sync::Orders do
  let(:account) { create(:ml_account, seller_id: 430_014_725) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let(:from) { Time.zone.parse("2026-07-24") }

  it "lê os pedidos e soma linhas do mesmo pedido/anúncio (quantidade soma; preço/tarifa em média ponderada)" do
    stub_request(:get, "https://api.mercadolibre.com/orders/search")
      .with(query: hash_including(offset: "0"))
      .to_return(status: 200, body: ml_fixture("orders_search"))

    result = described_class.call(client, account, from: from)

    expect(result.ok).to be true
    expect(result.order_ids).to match_array([ 2_000_000_001, 2_000_000_002, 2_000_000_003 ])
    expect(result.notes).to eq([])

    order = MlOrder.find(2_000_000_001)
    expect(order.status).to eq("paid")
    expect(order.total_amount.to_f).to eq(299.8)

    # As 2 linhas do pedido 2000000001 pro mesmo anúncio são somadas.
    line = MlOrderItem.find_by(order_id: 2_000_000_001, item_id: "MLB1000000001")
    expect(line.quantity).to eq(2)
    expect(line.unit_price.to_f).to eq(149.9)
    expect(line.sale_fee.to_f).to eq(24.73)
  end

  it "para quando a página vem com menos de 50 resultados" do
    stub_request(:get, "https://api.mercadolibre.com/orders/search")
      .with(query: hash_including(offset: "0"))
      .to_return(status: 200, body: ml_fixture("orders_search")) # 3 resultados, < 50

    described_class.call(client, account, from: from)

    expect(WebMock).to have_requested(:get, %r{\Ahttps://api\.mercadolibre\.com/orders/search}).once
  end

  it "para quando offset + 50 alcança paging.total, mesmo com página cheia" do
    orders = Array.new(50) do |i|
      { "id" => 3_000_000_000 + i, "status" => "paid", "date_created" => "2026-09-01T00:00:00.000-03:00",
        "date_closed" => nil, "total_amount" => 10.0, "order_items" => [] }
    end
    full_page = { query: "", display: "complete", paging: { total: 50, offset: 0, limit: 50 }, results: orders }.to_json

    stub_request(:get, "https://api.mercadolibre.com/orders/search")
      .with(query: hash_including(offset: "0"))
      .to_return(status: 200, body: full_page)

    described_class.call(client, account, from: from)

    expect(WebMock).to have_requested(:get, %r{\Ahttps://api\.mercadolibre\.com/orders/search}).once
  end

  it "erro numa página marca ok: false, guarda nota e para a paginação (parcial fica salvo)" do
    stub_request(:get, %r{\Ahttps://api\.mercadolibre\.com/orders/search})
      .to_return(status: 500, body: "erro")

    result = described_class.call(client, account, from: from)

    expect(result.ok).to be false
    expect(result.notes.first).to include("pedidos")
    expect(MlOrder.count).to eq(0)
  end
end
