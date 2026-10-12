require "rails_helper"

RSpec.describe Ml::Sync::FullStock do
  let(:account) { create(:ml_account) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { nil }) }
  let(:stock_body) { ml_fixture("fulfillment_stock") }

  def full_item(item_id, refs, status: "active", logistic: "fulfillment")
    create(:ml_item, ml_account: account, item_id: item_id, status: status, logistic_type: logistic, inventory_refs: refs)
  end

  def stub_stock(inventory_id, body: stock_body, status: 200)
    stub_request(:get, "https://api.mercadolibre.com/inventories/#{inventory_id}/stock/fulfillment")
      .to_return(status: status, body: body)
  end

  it "lê o estoque de cada inventory_id dos anúncios Full e grava disponível, indisponível e total" do
    full_item("MLB1", [ { "sku" => "LUN-001", "inventory_id" => "ABCD1234" } ])
    stub_stock("ABCD1234")

    result = described_class.call(client, account)

    expect(result.count).to eq(1)
    stock = MlFullStock.find_by(ml_account: account, inventory_id: "ABCD1234")
    expect(stock).to have_attributes(available_units: 9, not_available_units: 3, total_units: 12)
    expect(stock.not_available_detail.first).to include("status" => "damaged")
  end

  it "ignora anúncios que não são Full ou não estão ativos/pausados" do
    full_item("MLB2", [ { "sku" => "X", "inventory_id" => "INV-2" } ], logistic: "drop_off")
    full_item("MLB3", [ { "sku" => "Y", "inventory_id" => "INV-3" } ], status: "closed")

    result = described_class.call(client, account)

    expect(result.count).to eq(0)
    expect(WebMock).not_to have_requested(:get, /inventories/)
  end

  it "lê uma vez só o inventory compartilhado por vários anúncios" do
    full_item("MLB4", [ { "sku" => "S", "inventory_id" => "SHARED" } ])
    full_item("MLB5", [ { "sku" => "S", "inventory_id" => "SHARED" } ])
    stub_stock("SHARED")

    described_class.call(client, account)

    expect(WebMock).to have_requested(:get, /SHARED/).once
  end

  it "atualiza o que já existe sem duplicar" do
    full_item("MLB6", [ { "sku" => "S", "inventory_id" => "ABCD1234" } ])
    MlFullStock.create!(ml_account: account, inventory_id: "ABCD1234", available_units: 1, synced_at: 1.day.ago)
    stub_stock("ABCD1234")

    described_class.call(client, account)

    expect(MlFullStock.where(inventory_id: "ABCD1234").count).to eq(1)
    expect(MlFullStock.find_by(inventory_id: "ABCD1234").available_units).to eq(9)
  end

  it "erro de um inventory vira nota e os outros seguem" do
    full_item("MLB7", [ { "sku" => "A", "inventory_id" => "ABCD1234" }, { "sku" => "B", "inventory_id" => "BAD" } ])
    stub_stock("ABCD1234")
    stub_stock("BAD", body: "{}", status: 404)

    result = described_class.call(client, account)

    expect(result.count).to eq(1)
    expect(result.notes.join).to include("BAD")
  end
end
