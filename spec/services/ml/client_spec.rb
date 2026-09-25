require "rails_helper"

RSpec.describe Ml::Client do
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:client) { described_class.new(access_token: "APP_USR-token-123", sleeper: sleeper) }

  describe "autenticação" do
    it "manda o access_token no header Authorization" do
      stub_request(:get, "https://api.mercadolibre.com/users/me")
        .with(headers: { "Authorization" => "Bearer APP_USR-token-123" })
        .to_return(status: 200, body: ml_fixture("users_me"))

      client.me

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/me")
        .with(headers: { "Authorization" => "Bearer APP_USR-token-123" })
    end
  end

  describe "#items_scan" do
    it "usa search_type=scan, limit=100 e passa scroll_id quando informado" do
      stub_request(:get, "https://api.mercadolibre.com/users/430014725/items/search")
        .with(query: { search_type: "scan", limit: "100", scroll_id: "scroll-1" })
        .to_return(status: 200, body: ml_fixture("items_search_scan_2"))

      client.items_scan(430014725, scroll_id: "scroll-1")

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/430014725/items/search")
        .with(query: { search_type: "scan", limit: "100", scroll_id: "scroll-1" })
    end

    it "sem scroll_id não manda o parâmetro" do
      stub_request(:get, "https://api.mercadolibre.com/users/430014725/items/search")
        .with(query: { search_type: "scan", limit: "100" })
        .to_return(status: 200, body: ml_fixture("items_search_scan_1"))

      client.items_scan(430014725)

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/430014725/items/search")
        .with(query: { search_type: "scan", limit: "100" })
    end
  end

  describe "#items_multiget" do
    it "manda ids separados por vírgula e a lista exata de attributes da SPEC" do
      expected_attributes = %w[
        id title status sub_status price original_price available_quantity sold_quantity
        listing_type_id category_id shipping catalog_listing permalink thumbnail
        seller_custom_field attributes variations pictures video_id health date_created last_updated
      ].join(",")

      stub_request(:get, "https://api.mercadolibre.com/items")
        .with(query: { ids: "MLB1,MLB2", attributes: expected_attributes })
        .to_return(status: 200, body: ml_fixture("items_multiget"))

      result = client.items_multiget(%w[MLB1 MLB2])

      expect(result).to be_an(Array)
      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/items")
        .with(query: { ids: "MLB1,MLB2", attributes: expected_attributes })
    end
  end

  describe "#orders_search" do
    it "manda seller, order.date_created.from em ISO-8601, sort=date_desc, limit=50 e offset" do
      from = Time.utc(2026, 7, 24, 0, 0, 0)

      stub_request(:get, "https://api.mercadolibre.com/orders/search")
        .with(query: {
          seller: "430014725",
          "order.date_created.from" => from.iso8601,
          sort: "date_desc",
          limit: "50",
          offset: "0"
        })
        .to_return(status: 200, body: ml_fixture("orders_search"))

      client.orders_search(430014725, from: from, offset: 0)

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/orders/search")
        .with(query: {
          seller: "430014725",
          "order.date_created.from" => from.iso8601,
          sort: "date_desc",
          limit: "50",
          offset: "0"
        })
    end
  end

  describe "#item_performance" do
    it "usa a rota no singular /item/{id}/performance" do
      stub_request(:get, "https://api.mercadolibre.com/item/MLB1000000001/performance")
        .to_return(status: 200, body: ml_fixture("item_performance"))

      client.item_performance("MLB1000000001")

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/item/MLB1000000001/performance")
    end
  end

  describe "#listing_prices" do
    it "manda price, listing_type_id e category_id no site MLB" do
      stub_request(:get, "https://api.mercadolibre.com/sites/MLB/listing_prices")
        .with(query: { price: "149.9", listing_type_id: "gold_pro", category_id: "MLB1234" })
        .to_return(status: 200, body: ml_fixture("listing_prices"))

      client.listing_prices(price: 149.9, listing_type_id: "gold_pro", category_id: "MLB1234")

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/sites/MLB/listing_prices")
        .with(query: { price: "149.9", listing_type_id: "gold_pro", category_id: "MLB1234" })
    end
  end

  describe "#shipping_free" do
    it "manda item_id, free_shipping, item_price e verbose=true" do
      stub_request(:get, "https://api.mercadolibre.com/users/430014725/shipping_options/free")
        .with(query: { item_id: "MLB1000000001", free_shipping: "true", item_price: "149.9", verbose: "true" })
        .to_return(status: 200, body: ml_fixture("shipping_options_free"))

      client.shipping_free(430014725, item_id: "MLB1000000001", free_shipping: true, item_price: 149.9)

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/430014725/shipping_options/free")
        .with(query: { item_id: "MLB1000000001", free_shipping: "true", item_price: "149.9", verbose: "true" })
    end
  end

  describe "retentativa" do
    it "429, 429 e 200 dá certo com 3 chamadas, esperando 0.9 x tentativa entre elas" do
      stub_request(:get, "https://api.mercadolibre.com/users/me")
        .to_return({ status: 429, body: "" }, { status: 429, body: "" }, { status: 200, body: ml_fixture("users_me") })

      result = client.me

      expect(result["nickname"]).to eq("LUNNA_SHOP")
      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/me").times(3)
      expect(sleeps).to eq([ 0.9, 1.8 ])
    end

    it "500 três vezes vira Error depois de exatamente 3 chamadas" do
      stub_request(:get, "https://api.mercadolibre.com/users/me")
        .to_return(status: 500, body: "erro interno")

      expect { client.me }.to raise_error(Ml::Client::Error) do |error|
        expect(error.status).to eq(500)
        expect(error.path).to eq("/users/me")
      end

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/me").times(3)
      expect(sleeps).to eq([ 0.9, 1.8 ])
    end

    it "400 vira erro na 1ª chamada, sem repetir" do
      stub_request(:get, "https://api.mercadolibre.com/users/me")
        .to_return(status: 400, body: "requisição inválida")

      expect { client.me }.to raise_error(Ml::Client::Error)

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/me").times(1)
      expect(sleeps).to eq([])
    end

    it "404 vira NotFound, sem repetir" do
      stub_request(:get, "https://api.mercadolibre.com/item/MLB404/performance")
        .to_return(status: 404, body: "not found")

      expect { client.item_performance("MLB404") }.to raise_error(Ml::Client::NotFound)

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/item/MLB404/performance").times(1)
      expect(sleeps).to eq([])
    end

    it "o erro nunca inclui o access_token" do
      stub_request(:get, "https://api.mercadolibre.com/users/me")
        .to_return(status: 400, body: "requisição inválida")

      expect { client.me }.to raise_error(Ml::Client::Error) do |error|
        expect(error.message).not_to include("APP_USR-token-123")
      end
    end
  end
end
