require "rails_helper"

RSpec.describe Ml::Sync::Shipments do
  let(:account) { create(:ml_account) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }

  def order(id, shipping_id:, shipment: nil, synced: nil, created: 1.day.ago)
    MlOrder.create!(order_id: id, ml_account: account, status: "paid", date_created: created,
      shipping_id: shipping_id, shipment: shipment, shipment_synced_at: synced)
  end

  def stub_shipment(id, status: "shipped")
    stub_request(:get, "https://api.mercadolibre.com/shipments/#{id}").to_return(status: 200, body: {
      id: id, status: status, substatus: nil, logistic_type: "fulfillment", tracking_number: "ABC123",
      status_history: { date_handling: "2026-10-01T10:00:00.000-03:00" },
      shipping_option: { name: "Prioritário", cost: 0, list_cost: 21.75, estimated_delivery_final: { date: "2026-10-20T00:00:00.000-03:00" } },
      receiver_address: { receiver_name: "Fulano da Silva", receiver_phone: "11999999999", address_line: "Rua X 1",
                          city: { name: "Itabaraba" }, state: { name: "Bahia" } }
    }.to_json)
    stub_request(:get, "https://api.mercadolibre.com/shipments/#{id}/costs").to_return(status: 200, body: {
      gross_amount: 21.75, receiver: { cost: 0 }, senders: [ { cost: 21.75, discounts: [] } ]
    }.to_json)
  end

  it "grava o envio sem dados pessoais do comprador, com o frete pago pelo vendedor" do
    order(1, shipping_id: 900)
    stub_shipment(900)

    result = described_class.call(client, account, limit: 10)

    expect(result.count).to eq(1)
    shipment = MlOrder.find(1).shipment
    expect(shipment).to include("status" => "shipped", "logistic_type" => "fulfillment", "seller_cost" => 21.75,
      "destination_city" => "Itabaraba", "destination_state" => "Bahia", "tracking_number" => "ABC123")
    expect(shipment.to_json).not_to include("Fulano", "11999999999", "Rua X")
    expect(MlOrder.find(1).shipment_synced_at).to be_present
  end

  it "relê o envio já final quando a venda muda depois da leitura (cancelamento, reclamação, devolução)" do
    order(1, shipping_id: 950, shipment: { "status" => "delivered" }, synced: 2.days.ago)
    MlOrder.find(1).update_columns(payload: { "last_updated" => 1.hour.ago.iso8601 })
    order(2, shipping_id: 951, shipment: { "status" => "delivered" }, synced: 1.hour.ago)
    MlOrder.find(2).update_columns(payload: { "last_updated" => 2.days.ago.iso8601 })

    expect(described_class.pending(account).pluck(:order_id)).to eq([ 1 ])
  end

  it "não relê envio já entregue, mas relê o que ainda está em andamento depois de 2 horas" do
    order(1, shipping_id: 901, shipment: { "status" => "delivered" }, synced: 5.hours.ago)
    order(2, shipping_id: 902, shipment: { "status" => "shipped" }, synced: 5.hours.ago)
    order(3, shipping_id: 903, shipment: { "status" => "shipped" }, synced: 10.minutes.ago)
    stub_shipment(902, status: "delivered")

    described_class.call(client, account, limit: 10)

    expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/shipments/902")
    expect(WebMock).not_to have_requested(:get, "https://api.mercadolibre.com/shipments/901")
    expect(WebMock).not_to have_requested(:get, "https://api.mercadolibre.com/shipments/903")
  end

  it "respeita o limite, começando pelos pedidos mais novos, e informa quantos faltam" do
    order(1, shipping_id: 911, created: 3.days.ago)
    order(2, shipping_id: 912, created: 1.day.ago)
    stub_shipment(912)

    result = described_class.call(client, account, limit: 1)

    expect(result.count).to eq(1)
    expect(result.remaining).to eq(1)
    expect(MlOrder.find(2).shipment).to be_present
    expect(MlOrder.find(1).shipment).to be_nil
  end

  it "envio que o ML não encontra (404) é marcado como indisponível e não é tentado de novo" do
    order(1, shipping_id: 920)
    stub_request(:get, "https://api.mercadolibre.com/shipments/920").to_return(status: 404, body: "{}")

    described_class.call(client, account, limit: 10)

    expect(MlOrder.find(1).shipment).to eq("status" => "unavailable")
    expect(described_class.pending(account)).to be_empty # relê só depois de 2 horas
  end

  it "falha de conexão/erro do ML vira nota e não derruba a rodada" do
    order(1, shipping_id: 930)
    stub_request(:get, "https://api.mercadolibre.com/shipments/930").to_return(status: 500, body: "erro")

    result = described_class.call(client, account, limit: 10)

    expect(result.count).to eq(0)
    expect(result.notes.first).to include("envio 930")
  end
end
