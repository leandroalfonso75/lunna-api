require "rails_helper"

RSpec.describe Ml::Sync::ClaimsCenter do
  let(:account) { create(:ml_account, seller_id: 430) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let(:api) { "https://api.mercadolibre.com/post-purchase" }

  def claim(id, updated: "2026-11-02T10:00:00.000-03:00", status: "opened", type: "mediations", resource: "order", resource_id: 9001, related: [ "return" ])
    { id: id, resource: resource, resource_id: resource_id, status: status, type: type, stage: "dispute", reason_id: "PDD9941",
      parent_id: nil, fulfilled: true, quantity_type: "total", site_id: "MLB", date_created: "2026-11-01T10:00:00.000-03:00",
      last_updated: updated, players: [ { role: "complainant", type: "buyer", user_id: 1 }, { role: "respondent", type: "seller", user_id: 430 } ],
      resolution: nil, related_entities: related }
  end

  def stub_search(rows, total: rows.size)
    stub_request(:get, "#{api}/v1/claims/search").with(query: hash_including({ "player_role" => "respondent", "player_user_id" => "430" }))
      .to_return(status: 200, body: { paging: { total: total, offset: 0, limit: 100 }, data: rows }.to_json)
  end

  def stub_details(id, body = claim(id))
    stub_request(:get, "#{api}/v1/claims/#{id}").to_return(status: 200, body: body.to_json)
    stub_request(:get, "#{api}/v1/claims/#{id}/detail").to_return(status: 200, body: { title: "Envie o produto", description: "Faça o envio", action_responsible: "seller", due_date: "2026-11-05T23:59:00.000-03:00", problem: "x" }.to_json)
    stub_request(:get, "#{api}/v1/claims/#{id}/messages").to_return(status: 200, body: [ { sender_role: "mediator", receiver_role: "respondent", message: "Olá <strong>vendedor</strong>", message_date: "2026-11-01T11:00:00.000-03:00", attachments: [ { filename: "a.jpg", original_filename: "foto.jpg", type: "image/jpeg", size: 10 } ] } ].to_json)
    stub_request(:get, "#{api}/v1/claims/#{id}/status_history").to_return(status: 200, body: [ { date: "2026-11-01T10:00:00.000-03:00", stage: "claim", status: "opened", change_by: "complainant" } ].to_json)
    stub_request(:get, "#{api}/v1/claims/#{id}/actions-history").to_return(status: 200, body: [ { action_name: "open_dispute", player_role: "complainant" } ].to_json)
    stub_request(:get, "#{api}/v1/claims/#{id}/expected-resolutions").to_return(status: 200, body: [ { player_role: "complainant", expected_resolution: "return_product", status: "pending" } ].to_json)
    stub_request(:get, "#{api}/v1/claims/#{id}/evidences").to_return(status: 500, body: "{}") # parte recusada não impede o resto
    stub_request(:get, "#{api}/v1/claims/#{id}/changes").to_return(status: 200, body: { paging: {}, data: [ { field: "stage" } ] }.to_json)
    stub_request(:get, "#{api}/v1/claims/#{id}/affects-reputation").to_return(status: 200, body: { affects_reputation: true, has_incentive: false }.to_json)
    stub_request(:get, "#{api}/v2/claims/#{id}/returns").to_return(status: 200, body: { id: 77, status: "label_generated" }.to_json)
    stub_request(:get, "#{api}/v1/claims/reasons/PDD9941").to_return(status: 200, body: { id: "PDD9941", name: "different_color", detail: "Não é da cor que escolhi", flow: "post_purchase_delivered" }.to_json)
  end

  it "lista todas as reclamações e importa os detalhes (mensagens, histórico, reputação, devolução, motivo)" do
    cancel = claim(2, status: "closed", type: "cancel_purchase", resource: "shipment", resource_id: 555, related: [])
    stub_search([ claim(1), cancel ])
    stub_details(1)
    stub_details(2, cancel)

    result = described_class.call(client, account)

    expect(result).to have_attributes(listed: 2, detailed: 2, remaining: 0) # a aberta só volta a ser lida depois de 1 h
    c = account.ml_claims.find_by(claim_id: 1)
    expect(c).to have_attributes(claim_type: "mediations", stage: "dispute", status: "opened", order_id: 9001,
                                 detail_title: "Envie o produto", action_responsible: "seller", affects_reputation: true,
                                 reason_detail: "Não é da cor que escolhi", reason_flow: "post_purchase_delivered")
    expect(c.messages.first["message"]).to include("<strong>vendedor</strong>")
    expect(c.devolution).to include("id" => 77)
    expect(c.changes_log).to eq([ { "field" => "stage" } ])
    expect(c.detail_errors.keys).to eq([ "evidences" ])
    expect(account.ml_claims.find_by(claim_id: 2)).to have_attributes(order_id: nil, resource: "shipment", devolution: nil)
    expect(account.reload.claims_full_listed_at).to be_present
  end

  it "depois da lista completa, só relê as alteradas e para quando chega na última leitura" do
    account.update_columns(claims_full_listed_at: 1.hour.ago, claims_listed_at: Time.zone.parse("2026-11-02T12:00:00-03:00"))
    stub_search([ claim(3, updated: "2026-11-03T09:00:00.000-03:00"), claim(1, updated: "2026-10-01T09:00:00.000-03:00") ], total: 500)
    stub_details(3)
    stub_details(1)

    result = described_class.call(client, account, details_limit: 0)

    expect(result.listed).to eq(2)
    expect(a_request(:get, "#{api}/v1/claims/search").with(query: hash_including({ "sort" => "last_updated:desc" }))).to have_been_made.once
  end
end
