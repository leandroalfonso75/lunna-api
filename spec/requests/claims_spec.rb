require "rails_helper"

RSpec.describe "/api/claims", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  def claim(id, **attrs)
    MlClaim.create!({ ml_account: account, claim_id: id, claim_type: "mediations", stage: "dispute", status: "opened",
                      reason_detail: "Não é da cor que escolhi", date_created: 1.day.ago, last_updated: 1.hour.ago }.merge(attrs))
  end

  it "lista as reclamações com a venda ligada (pelo pedido ou pelo envio) e o andamento da importação" do
    MlOrder.create!(order_id: 10, ml_account: account, status: "paid", date_created: 2.days.ago, total_amount: 50, shipping_id: 700,
                    buyer_nickname: "COMPRA1", buyer_name: "Maria")
    MlOrderItem.create!(order_id: 10, item_id: "MLB1", sku: "SKU-1", title: "Batom", quantity: 1, unit_price: 50, sale_fee: 5)
    claim(1, resource: "order", resource_id: 10, order_id: 10, details_synced_at: Time.current, affects_reputation: true, action_responsible: "seller")
    claim(2, resource: "shipment", resource_id: 700, status: "closed", claim_type: "cancel_purchase", date_created: 2.days.ago)
    claim(3, resource: "order", resource_id: 999, order_id: 999, date_created: 3.days.ago)
    MlClaim.create!(ml_account: create(:ml_account), claim_id: 4)

    get "/api/claims", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 1, 2, 3 ])
    first = json["claims"].first
    expect(first).to include("type_label" => "Reclamação", "stage_label" => "Mediação", "status_label" => "Aberta",
                             "action_responsible_label" => "Você", "affects_reputation" => true, "detailed" => true)
    expect(first["order"]).to include("order_id" => 10, "buyer_name" => "Maria")
    expect(first["order"]["item"]).to include("sku" => "SKU-1")
    expect(json["claims"][1]["order"]).to include("order_id" => 10) # pelo envio
    expect(json["claims"][2]["order"]).to be_nil # venda fora do Lunna
    expect(json["import"]).to include("total" => 3, "detailed" => 1, "open" => 2)
  end

  it "busca pelo número da venda, pelo comprador e pelo motivo" do
    MlOrder.create!(order_id: 10, ml_account: account, status: "paid", date_created: 2.days.ago, shipping_id: 700, buyer_nickname: "COMPRA1")
    claim(1, resource: "shipment", resource_id: 700)
    claim(2, reason_detail: "Chegou quebrado")

    get "/api/claims", params: { account_id: account.id, q: "10" }, headers: auth_headers(member)
    expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 1 ])

    get "/api/claims", params: { account_id: account.id, q: "compra1" }, headers: auth_headers(member)
    expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 1 ])

    get "/api/claims", params: { account_id: account.id, q: "quebrado" }, headers: auth_headers(member)
    expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 2 ])
  end

  it "detalhe com tudo o que o ML informou, mensagens sem HTML; de outra conta é 404" do
    claim(1, messages: [ { "sender_role" => "mediator", "receiver_role" => "respondent", "message" => "Olá <strong>vendedor</strong><br>tudo bem?",
                           "message_date" => "2026-11-01T11:00:00.000-03:00", "attachments" => [ { "original_filename" => "foto.jpg" } ] } ],
             expected_resolutions: [ { "expected_resolution" => "return_product", "player_role" => "complainant" } ],
             raw: { "id" => 1 }, reason: { "id" => "PDD9941" })

    get "/api/claims/1", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(json["messages"].first).to include("sender_label" => "Mercado Livre", "text" => "Olá vendedor\ntudo bem?")
    expect(json["messages"].first["attachments"].first).to include("original_filename" => "foto.jpg")
    expect(json["expected_resolutions"].first).to include("label" => "Devolver o produto")
    expect(json).to include("raw" => { "id" => 1 }, "reason_info" => { "id" => "PDD9941" })

    other = MlClaim.create!(ml_account: create(:ml_account), claim_id: 99)
    get "/api/claims/#{other.claim_id}", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:not_found)
  end
end
