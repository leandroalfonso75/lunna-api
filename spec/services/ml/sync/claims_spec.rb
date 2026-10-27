require "rails_helper"

RSpec.describe Ml::Sync::Claims do
  let(:account) { create(:ml_account) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let(:base) { "https://api.mercadolibre.com/post-purchase" }

  def order(id, mediations:, synced: nil, claims: nil, last_updated: 1.hour.ago)
    MlOrder.create!(order_id: id, ml_account: account, status: "cancelled", date_created: 3.days.ago,
      payload: { "mediations" => mediations.map { |m| { "id" => m } }, "last_updated" => last_updated.iso8601 },
      claims: claims, claims_synced_at: synced)
  end

  def stub_claim(id, related: [], status: "closed")
    stub_request(:get, "#{base}/v1/claims/#{id}").to_return(status: 200, body: {
      id: id, type: "mediations", stage: "dispute", status: status, reason_id: "PDD9947", related_entities: related,
      players: [ { role: "complainant", type: "buyer", user_id: 1 }, { role: "respondent", type: "seller", user_id: 2 } ],
      resolution: { reason: "item_returned", benefited: [ "complainant" ], closed_by: "mediator", applied_coverage: false },
      date_created: "2026-10-12T14:02:52.000-04:00"
    }.to_json)
  end

  before do
    stub_request(:get, "#{base}/v1/claims/reasons/PDD9947").to_return(status: 200,
      body: { id: "PDD9947", name: "damaged", detail: "A embalagem estava danificada", flow: "post_purchase_delivered" }.to_json)
  end

  it "guarda a reclamação com o motivo em texto, o resultado e a devolução" do
    order(1, mediations: [ 77 ])
    stub_claim(77, related: [ "return" ])
    stub_request(:get, "#{base}/v2/claims/77/returns").to_return(status: 200, body: {
      status: "shipped", subtype: "return_total", status_money: "retained", shipments: [ { type: "return", status: "shipped", tracking_number: "AP1" } ]
    }.to_json)

    result = described_class.call(client, account, limit: 10)

    expect(result.count).to eq(1)
    claim = MlOrder.find(1).claims.first
    expect(claim).to include("type" => "mediations", "reason" => "A embalagem estava danificada", "opened_by" => "buyer", "status" => "closed")
    expect(claim["resolution"]).to include("reason" => "item_returned", "benefited" => [ "complainant" ])
    expect(claim["return"]).to include("status" => "shipped", "status_money" => "retained")
  end

  it "relê quando o pedido muda depois da leitura ou enquanto a reclamação está aberta" do
    order(1, mediations: [ 1 ], synced: 1.day.ago, claims: [ { "status" => "closed" } ], last_updated: 2.days.ago) # nada mudou
    order(2, mediations: [ 2 ], synced: 1.day.ago, claims: [ { "status" => "closed" } ], last_updated: 1.hour.ago) # pedido mudou
    order(3, mediations: [ 3 ], synced: 3.hours.ago, claims: [ { "status" => "opened" } ], last_updated: 1.day.ago) # aberta
    order(4, mediations: [ 4 ], synced: 10.minutes.ago, claims: [ { "status" => "opened" } ], last_updated: 1.day.ago) # lida agora
    order(5, mediations: [], synced: nil)

    expect(described_class.pending(account).pluck(:order_id)).to contain_exactly(2, 3)
  end
end
