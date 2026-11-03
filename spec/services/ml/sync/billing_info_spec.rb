require "rails_helper"

RSpec.describe Ml::Sync::BillingInfo do
  let(:account) { create(:ml_account) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }

  def order(id, created: 1.day.ago)
    MlOrder.create!(order_id: id, ml_account: account, status: "paid", date_created: created)
  end

  def stub_billing(id, doc_type: "CPF", doc: "12345678901")
    stub_request(:get, "https://api.mercadolibre.com/orders/#{id}/billing_info").to_return(status: 200, body: {
      billing_info: {
        doc_type: doc_type, doc_number: doc,
        additional_info: [
          { type: "FIRST_NAME", value: "Maria" }, { type: "LAST_NAME", value: "Souza Lima" },
          { type: "CITY_NAME", value: "Itabaraba" }, { type: "STATE_CODE", value: "BA" },
          { type: "STREET_NAME", value: "Rua X" }, { type: "STREET_NUMBER", value: "10" }, { type: "ZIP_CODE", value: "44600000" }
        ]
      }
    }.to_json)
  end

  it "guarda nome, documento e cidade/UF do comprador e descarta o endereço" do
    order(1)
    stub_billing(1)

    result = described_class.call(client, account, limit: 10)

    expect(result.count).to eq(1)
    o = MlOrder.find_by(order_id: 1)
    expect(o).to have_attributes(buyer_name: "Maria Souza Lima", buyer_doc_type: "CPF", buyer_doc_number: "12345678901",
                                 buyer_city: "Itabaraba", buyer_state: "BA", billing_synced_at: be_present)
    expect(o.attributes.values.map(&:to_s).join).not_to include("Rua X")
  end

  it "pedido sem faturamento (404) não é tentado de novo; permissão negada para a rodada" do
    order(1, created: 1.day.ago)
    order(2, created: 2.days.ago)
    stub_request(:get, "https://api.mercadolibre.com/orders/1/billing_info").to_return(status: 404, body: "{}")
    stub_request(:get, "https://api.mercadolibre.com/orders/2/billing_info").to_return(status: 403, body: "{}")

    result = described_class.call(client, account, limit: 10)

    expect(MlOrder.find_by(order_id: 1).billing_synced_at).to be_present
    expect(MlOrder.find_by(order_id: 2).billing_synced_at).to be_nil
    expect(result.notes.first).to include("faturamento 2")
  end
end
