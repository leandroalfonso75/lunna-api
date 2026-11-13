require "rails_helper"

RSpec.describe "/api/claims/returns (card Devoluções)", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  def claim(id, **attrs)
    MlClaim.create!({ ml_account: account, claim_id: id, claim_type: "mediations", stage: "dispute", status: "closed",
                      details_synced_at: Time.current, date_created: 5.days.ago, last_updated: 1.hour.ago,
                      reason: { "name" => "repentant_buyer" } }.merge(attrs))
  end

  def order(id, shipping_id:, refunded:)
    MlOrder.create!(order_id: id, ml_account: account, status: "paid", date_created: 10.days.ago, total_amount: 100, shipping_id: shipping_id,
                    buyer_nickname: "COMPRA#{id}", shipment: { "logistic_type" => "fulfillment" },
                    payload: { "payments" => [ { "transaction_amount" => 100, "total_paid_amount" => 100, "transaction_amount_refunded" => refunded ? 100 : 0 } ] })
    MlOrderItem.create!(order_id: id, item_id: "MLB#{id}", sku: "SKU-#{id}", title: "Produto #{id}", quantity: 1, unit_price: 100, sale_fee: 10)
  end

  def charge(detail_id, type, sub, amount, order_id: nil, shipment_id: nil, label: "x")
    MlBillingCharge.create!(ml_account: account, detail_id: detail_id, period_key: "2026-11-01", detail_type: type, detail_sub_type: sub,
                            transaction_detail: label, amount: amount, order_id: order_id, shipment_id: shipment_id, charged_at: 2.days.ago)
  end

  before do
    # 1: devolvida, com frete de envio retido (cobrança sem cancelamento) e frete de devolução cobrado pelo ML
    order(1, shipping_id: 701, refunded: true)
    claim(1, order_id: 1, resource: "order", resource_id: 1, return_cost: 43.5, return_cost_at: Time.current,
             devolution: { "status" => "delivered", "status_money" => "refunded", "date_closed" => 1.day.ago.iso8601, "shipments" => [ { "type" => "return", "shipment_id" => 801 } ] })
    charge(11, "CHARGE", "CFFE", 21.75, order_id: 1, shipment_id: "701", label: "Tarifa de envio extra ou intermunicipal")
    charge(12, "CHARGE", "CVVML", 18.05, order_id: 1, shipment_id: "701", label: "Custo por vender no Mercado Livre")
    charge(13, "BONUS", "BVVML", 18.05, order_id: 1, shipment_id: "701", label: "Cancelamento do Custo por vender no Mercado Livre")
    # 2: devolvida sem custo: frete de envio cancelado pelo ML, devolução grátis
    order(2, shipping_id: 702, refunded: true)
    claim(2, order_id: 2, resource: "order", resource_id: 2, return_cost: 0, return_cost_at: Time.current,
             devolution: { "status" => "delivered", "status_money" => "refunded", "shipments" => [ { "type" => "return", "shipment_id" => 802 } ] })
    charge(21, "CHARGE", "CFFE", 7.35, order_id: 2, shipment_id: "702", label: "Tarifa de envio extra ou intermunicipal")
    charge(22, "BONUS", "BFFE", 7.35, order_id: 2, shipment_id: "702", label: "Cancelamento da tarifa de envio extra ou intermunicipal")
    # 3: expirada (comprador não postou); 4: a caminho; 5: autorizada sem devolução gerada e encerrada
    claim(3, devolution: { "status" => "expired", "status_money" => "retained" }, return_cost: 30.9, return_cost_at: Time.current)
    claim(4, status: "opened", devolution: { "status" => "shipped", "status_money" => "retained" })
    claim(5, actions_history: [ { "action_name" => "allow_return", "player_role" => "respondent" } ])
    claim(6, date_created: 400.days.ago, devolution: { "status" => "delivered", "status_money" => "refunded" }) # fora do período de 365d
  end

  it "separa expiradas, sem custo, com custos (itemizados) e em andamento, com totais; segue o período" do
    get "/api/claims/returns", params: { account_id: account.id, period: "365d" }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    tabs = json["tabs"]
    expect(tabs.transform_values { |rows| rows.map { |r| r["claim_id"] }.sort }).to eq(
      "expiradas" => [ 3, 5 ], "sem_custo" => [ 2 ], "com_custos" => [ 1 ], "em_andamento" => [ 4 ], "sem_nota" => [ 1, 2 ] # sem_nota: efetivadas ainda sem nota de devolução
    )
    costly = tabs["com_custos"].first
    expect(costly["costs"]["items"].map { |i| [ i["key"], i["amount"] ] }).to eq([ [ "frete_envio", 21.75 ], [ "frete_devolucao", 43.5 ] ])
    expect(costly["costs"]["total"]).to eq(65.25)
    expect(costly["refund"]).to include("key" => "integral", "amount" => 100.0)
    expect(costly["item"]).to include("sku" => "SKU-1")
    expect(costly["costs"]["statement"].size).to eq(3)
    expect(tabs["sem_custo"].first["costs"]).to include("items" => [], "total" => 0.0)
    expect(tabs["expiradas"].first["costs"]["items"]).to eq([]) # etiqueta não usada: o custo de devolução não conta
    expect(json["summary"]).to include("total_cost" => 65.25, "counts" => { "expiradas" => 2, "sem_custo" => 1, "com_custos" => 1, "em_andamento" => 1, "sem_nota" => 2 })
    expect(json["summary"]["by_kind"]).to eq("frete_envio" => 21.75, "frete_devolucao" => 43.5)

    get "/api/claims/returns", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["summary"]["counts"]["sem_custo"]).to eq(2) # sem período entra a de 400 dias
  end
end

RSpec.describe Ml::Sync::BillingCharges do
  let(:account) { create(:ml_account) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }

  it "lê os períodos e as páginas do extrato (respeitando a pausa) e grava cada linha ligada à venda e ao envio" do
    stub_request(:get, "https://api.mercadolibre.com/billing/integration/monthly/periods")
      .with(query: hash_including("group" => "ML", "document_type" => "BILL"))
      .to_return(status: 200, body: { results: [ { key: "2026-11-01" } ] }.to_json)
    row = { charge_info: { detail_id: 1, detail_type: "CHARGE", detail_sub_type: "CFFE", transaction_detail: "Tarifa de envio", detail_amount: 21.75, creation_date_time: "2026-11-01T10:00:00" },
            sales_info: [ { order_id: 2000, operation_id: 1 } ], shipping_info: { shipping_id: "701", pack_id: nil }, items_info: [ { item_id: "MLB1" } ],
            currency_info: { currency_id: "BRL" } }
    stub_request(:get, "https://api.mercadolibre.com/billing/integration/periods/key/2026-11-01/group/ML/details")
      .with(query: hash_including("offset" => "0")).to_return(status: 200, body: { total: 1001, results: [ row ] }.to_json)
    stub_request(:get, "https://api.mercadolibre.com/billing/integration/periods/key/2026-11-01/group/ML/details")
      .with(query: hash_including("offset" => "1000")).to_return(status: 200, body: { total: 1001, results: [ row.deep_merge(charge_info: { detail_id: 2 }) ] }.to_json)
    pauses = []

    result = described_class.call(client, account, sleeper: ->(s) { pauses << s })

    expect(result.count).to eq(2)
    expect(pauses).to eq([ 13, 13 ])
    expect(account.ml_billing_charges.pluck(:detail_id, :order_id, :shipment_id, :item_id, :amount)).to contain_exactly([ 1, 2000, 701, "MLB1", 21.75 ], [ 2, 2000, 701, "MLB1", 21.75 ])
    expect(account.reload.billing_synced_at).to be_present
    expect(described_class.due?(account)).to be(false)
  end
end
