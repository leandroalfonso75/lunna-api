require "rails_helper"

RSpec.describe Ml::Sync::Details do
  let(:account) { create(:ml_account, seller_id: 430_014_725) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let(:item) do
    create(:ml_item,
      ml_account: account, item_id: "MLB1000000001", category_id: "MLB1234",
      listing_type_id: "gold_pro", price: 149.9, free_shipping: true,
      attrs_filled: %w[BRAND MODEL COLOR SELLER_SKU])
  end

  def stub_category
    stub_request(:get, "https://api.mercadolibre.com/categories/MLB1234/attributes")
      .to_return(status: 200, body: ml_fixture("category_attributes"))
  end

  def stub_description(status: 200)
    stub_request(:get, "https://api.mercadolibre.com/items/MLB1000000001/description")
      .to_return(status: status, body: status == 200 ? ml_fixture("item_description") : "não encontrado")
  end

  def stub_sale_price(amount:, regular_amount: 149.9)
    stub_request(:get, "https://api.mercadolibre.com/items/MLB1000000001/sale_price")
      .with(query: hash_including("context" => "channel_marketplace"))
      .to_return(status: 200, body: { price_id: "1", amount: amount, regular_amount: regular_amount }.to_json)
  end

  def stub_suggestion(status: 200, suggested: 129.9)
    body = JSON.parse(ml_fixture("suggestions_details"))
    body["suggested_price"] = { "amount" => suggested }
    stub_request(:get, "https://api.mercadolibre.com/suggestions/items/MLB1000000001/details")
      .to_return(status: status, body: status == 200 ? body.to_json : "not found")
  end

  def stub_fee(price:)
    stub_request(:get, "https://api.mercadolibre.com/sites/MLB/listing_prices")
      .with(query: hash_including(price: price.to_s))
      .to_return(status: 200, body: ml_fixture("listing_prices"))
  end

  def stub_ship(item_price:, free_shipping:)
    stub_request(:get, "https://api.mercadolibre.com/users/430014725/shipping_options/free")
      .with(query: hash_including(item_price: item_price.to_s, free_shipping: free_shipping.to_s))
      .to_return(status: 200, body: ml_fixture("shipping_options_free"))
  end

  it "grava descrição, sale_price/regular_price, tarifa/frete no preço efetivo, atributos faltando e price_ref" do
    stub_category
    stub_description
    stub_sale_price(amount: 139.9)
    stub_suggestion(suggested: 129.9)
    stub_fee(price: 139.9)
    stub_ship(item_price: 139.9, free_shipping: true)
    stub_fee(price: 129.9)
    stub_ship(item_price: 129.9, free_shipping: true)

    described_class.call(client, account, [ item ])
    item.reload

    expect(item.description_len).to eq(JSON.parse(ml_fixture("item_description"))["plain_text"].length)
    expect(item.sale_price.to_f).to eq(139.9)
    expect(item.regular_price.to_f).to eq(149.9)
    expect(item.fee_now.to_f).to eq(23.08)
    expect(item.ship_cost.to_f).to eq(21.45)
    # BRAND/MODEL preenchidos, GTIN não → só GTIN falta como obrigatório;
    # COLOR preenchido, MATERIAL/POWER não → faltam como principais.
    expect(item.attrs_missing_required).to eq([ "Código universal de produto" ])
    expect(item.attrs_missing_main).to eq(%w[Material Potência])
    expect(item.price_ref["suggested"]).to eq(129.9)
    expect(item.price_ref["graph"].size).to eq(6)
    expect(item.fee_at_ref.to_f).to eq(23.08)
    expect(item.ship_at_ref.to_f).to eq(21.45)
    expect(item.details_checked_at).to be_present
  end

  it "descrição 404 vira description_len = 0 (não é falha)" do
    stub_category
    stub_description(status: 404)
    stub_sale_price(amount: 139.9)
    stub_suggestion(suggested: 129.9)
    stub_fee(price: 139.9)
    stub_ship(item_price: 139.9, free_shipping: true)
    stub_fee(price: 129.9)
    stub_ship(item_price: 129.9, free_shipping: true)

    result = described_class.call(client, account, [ item ])

    expect(result.notes).to eq([])
    expect(item.reload.description_len).to eq(0)
  end

  it "price_ref 404 vira nil (sem nota) e fee_at_ref/ship_at_ref ficam nil" do
    stub_category
    stub_description
    stub_sale_price(amount: 139.9)
    stub_suggestion(status: 404)
    stub_fee(price: 139.9)
    stub_ship(item_price: 139.9, free_shipping: true)

    result = described_class.call(client, account, [ item ])
    item.reload

    expect(result.notes).to eq([])
    expect(item.price_ref).to be_nil
    expect(item.fee_at_ref).to be_nil
    expect(item.ship_at_ref).to be_nil
  end

  it "fee_at_ref/ship_at_ref ficam nil quando o sugerido é igual ao efetivo (diff <= 0,009)" do
    stub_category
    stub_description
    stub_sale_price(amount: 129.9)
    stub_suggestion(suggested: 129.9)
    stub_fee(price: 129.9)
    stub_ship(item_price: 129.9, free_shipping: true)

    described_class.call(client, account, [ item ])
    item.reload

    expect(item.fee_at_ref).to be_nil
    expect(item.ship_at_ref).to be_nil
    expect(WebMock).to have_requested(:get, %r{\Ahttps://api\.mercadolibre\.com/sites/MLB/listing_prices\?}).once
  end

  it "sugerido >= 79 consulta o frete com free_shipping=true mesmo com o anúncio sem frete grátis" do
    item.update!(free_shipping: false)
    stub_category
    stub_description
    stub_sale_price(amount: 50.0)
    stub_suggestion(suggested: 79.00)
    stub_fee(price: 50.0)
    stub_ship(item_price: 50.0, free_shipping: false)
    stub_fee(price: 79.00)
    stub_ship(item_price: 79.00, free_shipping: true)

    described_class.call(client, account, [ item ])

    expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/430014725/shipping_options/free")
      .with(query: hash_including(item_price: "79.0", free_shipping: "true"))
  end

  it "sugerido < 79 (78,99) mantém o free_shipping atual do anúncio" do
    item.update!(free_shipping: false)
    stub_category
    stub_description
    stub_sale_price(amount: 50.0)
    stub_suggestion(suggested: 78.99)
    stub_fee(price: 50.0)
    stub_ship(item_price: 50.0, free_shipping: false)
    stub_fee(price: 78.99)
    stub_ship(item_price: 78.99, free_shipping: false)

    described_class.call(client, account, [ item ])

    expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/users/430014725/shipping_options/free")
      .with(query: hash_including(item_price: "78.99", free_shipping: "false"))
  end

  it "erro num sub-chamado vira nota, mas details_checked_at é gravado do mesmo jeito" do
    stub_description(status: 500)
    stub_category
    stub_sale_price(amount: 0)
    stub_fee(price: 149.9)
    stub_ship(item_price: 149.9, free_shipping: true)
    stub_suggestion(status: 404)

    result = described_class.call(client, account, [ item ])
    item.reload

    expect(result.notes.first).to include("descrição").and include("MLB1000000001")
    expect(item.details_checked_at).to be_present
    expect(item.description_len).to be_nil
    expect(item.fee_now.to_f).to eq(23.08)
  end
end
