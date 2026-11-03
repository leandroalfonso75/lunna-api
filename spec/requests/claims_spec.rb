require "rails_helper"

RSpec.describe "/api/claims", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
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

  it "devolução habilitada e efetivada: Devolvida, A caminho, Aguardando e Não devolvida" do
    now = Time.current
    ret = ->(status) { { "status" => status, "subtype" => "return_total", "shipments" => [ { "type" => "return", "status" => "x", "tracking_number" => "BR1" } ] } }
    claim(1, details_synced_at: now, devolution: ret.("delivered"), date_created: 1.day.ago)
    claim(2, details_synced_at: now, devolution: ret.("shipped"), date_created: 2.days.ago)
    claim(3, details_synced_at: now, devolution: ret.("label_generated"), date_created: 3.days.ago)
    claim(4, details_synced_at: now, devolution: ret.("expired"), date_created: 4.days.ago)
    claim(5, details_synced_at: now, actions_history: [ { "action_name" => "allow_return" } ], date_created: 5.days.ago)
    claim(8, details_synced_at: now, status: "closed", actions_history: [ { "action_name" => "allow_return" } ], date_created: 8.days.ago)
    claim(6, details_synced_at: now, date_created: 6.days.ago)
    claim(7, date_created: 7.days.ago)

    get "/api/claims", params: { account_id: account.id }, headers: auth_headers(member)

    got = json["claims"].to_h { |c| [ c["claim_id"], c["devolution_status"].slice("enabled", "label").values ] }
    expect(got).to eq(1 => [ true, "Devolvida" ], 2 => [ true, "A caminho" ], 3 => [ true, "Aguardando" ], 4 => [ true, "Não devolvida" ],
                      5 => [ true, "Aguardando" ], 6 => [ false ], 7 => [ nil ], 8 => [ true, "Não devolvida" ])
  end

  it "reembolso (integral, parcial, sem) e custo com frete na devolução" do
    now = Time.current
    pay = ->(amount, refunded) { { "payments" => [ { "status" => refunded.positive? ? "refunded" : "approved", "transaction_amount" => amount, "total_paid_amount" => amount, "transaction_amount_refunded" => refunded } ] } }
    MlOrder.create!(order_id: 10, ml_account: account, status: "cancelled", date_created: 2.days.ago, total_amount: 100, payload: pay.(100, 100))
    MlOrder.create!(order_id: 11, ml_account: account, status: "paid", date_created: 2.days.ago, total_amount: 100, payload: pay.(100, 40))
    MlOrder.create!(order_id: 12, ml_account: account, status: "paid", date_created: 2.days.ago, total_amount: 100, payload: pay.(100, 0))
    dev = { "status" => "delivered", "shipments" => [ { "type" => "return", "shipment_id" => 5 } ] }
    claim(1, order_id: 10, resource: "order", resource_id: 10, details_synced_at: now, devolution: dev, return_shipping: { "seller_cost" => 27.2 })
    claim(2, order_id: 11, resource: "order", resource_id: 11, details_synced_at: now, devolution: dev,
             return_shipping: { "seller_cost" => 27.2, "stated_cost" => 9.79 }, date_created: 2.days.ago)
    claim(3, order_id: 12, resource: "order", resource_id: 12, details_synced_at: now, status: "closed", date_created: 3.days.ago)
    # venda fora do Lunna: pelo que a reclamação diz
    claim(4, details_synced_at: now, expected_resolutions: [ { "expected_resolution" => "partial_coverage", "status" => "accepted" } ], date_created: 4.days.ago)

    get "/api/claims", params: { account_id: account.id }, headers: auth_headers(member)

    by = json["claims"].to_h { |c| [ c["claim_id"], c ] }
    expect(by[1]["refund"]).to include("key" => "integral", "label" => "Reembolso integral", "amount" => 100.0)
    expect(by[2]["refund"]).to include("key" => "parcial", "label" => "Reembolso parcial", "amount" => 40.0)
    expect(by[3]["refund"]).to include("key" => "sem", "label" => "Sem reembolso")
    expect(by[4]["refund"]).to include("key" => "parcial", "source" => "reclamacao")
    expect(by[1]["freight"]).to include("key" => "sim", "amount" => 27.2)
    expect(by[2]["freight"]).to include("key" => "sim", "amount" => 9.79, "source" => "mensagem do ML")
    expect(by[3]["freight"]).to include("key" => "nao")

    MlClaim.find_by(claim_id: 1).update!(devolution: dev.merge("status" => "expired"))
    MlClaim.find_by(claim_id: 2).update!(devolution: dev.merge("status" => "label_generated"))
    get "/api/claims", params: { account_id: account.id }, headers: auth_headers(member)
    by = json["claims"].to_h { |c| [ c["claim_id"], c ] }
    expect(by[1]["freight"]).to include("key" => "nao")
    expect(by[2]["freight"]).to include("key" => "previsto", "label" => "Sim (previsto)")
  end

  it "filtro de período (presets, mês e datas) e ordenação por coluna" do
    travel_to(Time.zone.local(2026, 11, 3, 12)) do
      now = Time.current
      claim(1, date_created: Time.zone.local(2026, 11, 2, 10), details_synced_at: now, affects_reputation: true, reason_detail: "Chegou quebrado",
               devolution: { "status" => "delivered" })
      claim(2, date_created: Time.zone.local(2026, 10, 20, 10), details_synced_at: now, affects_reputation: false, reason_detail: "Arrependimento",
               claim_type: "cancel_purchase")
      claim(3, date_created: Time.zone.local(2025, 5, 1, 10), reason_detail: "Antiga")

      get "/api/claims", params: { account_id: account.id }, headers: auth_headers(member)
      expect(json["total"]).to eq(3)
      expect(json["period"]).to include("preset" => "all")
      expect(json["months"].map { |m| m["label"] }).to eq(%w[11/2026 10/2026 05/2025])

      get "/api/claims", params: { account_id: account.id, period: "7d" }, headers: auth_headers(member)
      expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 1 ])

      get "/api/claims", params: { account_id: account.id, month: "2026-10" }, headers: auth_headers(member)
      expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 2 ])

      get "/api/claims", params: { account_id: account.id, from: "2025-01-01", to: "2025-12-31" }, headers: auth_headers(member)
      expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 3 ])

      get "/api/claims", params: { account_id: account.id, sort: "reason", dir: "asc" }, headers: auth_headers(member)
      expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 3, 2, 1 ]) # Antiga, Arrependimento, Chegou quebrado
      expect(json).to include("sort" => "reason", "dir" => "asc")

      get "/api/claims", params: { account_id: account.id, sort: "reputation", dir: "desc" }, headers: auth_headers(member)
      expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 1, 2, 3 ]) # afeta, não afeta, sem detalhe no fim

      get "/api/claims", params: { account_id: account.id, sort: "return_state", dir: "asc" }, headers: auth_headers(member)
      expect(json["claims"].first["claim_id"]).to eq(1)
    end
  end

  describe "A atender e responder" do
    let(:base) { "https://api.mercadolibre.com/post-purchase/v1/claims" }
    let(:seller_actions) { [ { "action" => "send_message_to_complainant", "due_date" => nil, "mandatory" => false }, { "action" => "refund", "mandatory" => false } ] }
    let(:players) { [ { "role" => "complainant", "type" => "buyer" }, { "role" => "respondent", "type" => "seller", "available_actions" => seller_actions } ] }

    before do
      claim(1, status: "opened", action_responsible: "seller", due_date: 2.days.from_now, players: players, details_synced_at: Time.current,
               detail: { "title" => "Responda o comprador", "description" => "Você tem até amanhã" },
               expected_resolutions: [ { "player_role" => "complainant", "expected_resolution" => "return_product" } ],
               messages: [ { "sender_role" => "complainant", "message" => "Veio errado", "message_date" => 1.hour.ago.iso8601 } ])
      claim(2, status: "opened", action_responsible: "complainant", due_date: 5.days.from_now, players: players, details_synced_at: Time.current)
      claim(3, status: "closed", action_responsible: "seller")
    end

    it "lista as que aguardam o vendedor, com prazo, ações liberadas, o que o comprador quer e a última mensagem" do
      get "/api/claims", params: { account_id: account.id, view: "atender" }, headers: auth_headers(member)

      expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 1 ])
      c = json["claims"].first
      expect(c).to include("to_attend" => true, "reply_targets" => [ "complainant" ], "buyer_wants" => [ "Devolver o produto" ])
      expect(c["what_to_do"]).to include("title" => "Responda o comprador")
      expect(c["last_message"]).to include("text" => "Veio errado")
      expect(c["seller_actions"].map { |a| a["label"] }).to eq([ "Mandar mensagem ao comprador", "Reembolsar o comprador" ])
      expect(json["attention"]).to eq("to_attend" => 1, "open" => 2, "can_reply" => 2)

      get "/api/claims", params: { account_id: account.id, view: "abertas" }, headers: auth_headers(member)
      expect(json["claims"].map { |c| c["claim_id"] }).to eq([ 1, 2 ]) # a atender primeiro, depois pelo prazo
    end

    it "responde no Mercado Livre só com confirmação, registra e relê a reclamação" do
      send = stub_request(:post, "#{base}/1/actions/send-message").with(body: { receiver_role: "complainant", message: "Olá, vamos resolver." }.to_json)
        .to_return(status: 201, body: { id: "m1" }.to_json)
      allow(Ml::OAuth).to receive(:refresh!)
      allow(Ml::Sync::ClaimsCenter).to receive(:fetch_details).and_return({})

      post "/api/claims/1/reply", params: { account_id: account.id, receiver_role: "complainant", message: "Olá, vamos resolver." }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(send).not_to have_been_made

      post "/api/claims/1/reply", params: { account_id: account.id, receiver_role: "complainant", message: "Olá, vamos resolver.", confirm: true }, headers: auth_headers(member)
      expect(response).to have_http_status(:forbidden)

      post "/api/claims/1/reply", params: { account_id: account.id, receiver_role: "complainant", message: "Olá, vamos resolver.", confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
      expect(send).to have_been_made.once
      expect(MlClaimReply.last).to have_attributes(claim_id: 1, receiver_role: "complainant", status: "sent", user_id: admin.id)
      expect(Ml::Sync::ClaimsCenter).to have_received(:fetch_details)
    end

    it "recusa destinatário que o ML não libera e registra a falha quando o ML recusa" do
      allow(Ml::OAuth).to receive(:refresh!)
      post "/api/claims/1/reply", params: { account_id: account.id, receiver_role: "mediator", message: "Oi", confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("mediador")
      expect(MlClaimReply.count).to eq(0)

      stub_request(:post, "#{base}/1/actions/send-message").to_return(status: 400, body: { message: "claim closed" }.to_json)
      post "/api/claims/1/reply", params: { account_id: account.id, receiver_role: "complainant", message: "Oi", confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:bad_gateway)
      expect(json["errors"].first).to include("claim closed")
      expect(MlClaimReply.last).to have_attributes(status: "failed")
    end
  end
end
