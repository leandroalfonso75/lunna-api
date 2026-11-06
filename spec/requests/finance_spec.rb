require "rails_helper"

RSpec.describe "/api/finance (seção Financeiro)", type: :request do
  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 2, min_margin_pct: 9) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }

  def order(id, date, price:, fee:, shipping:, refunded: 0, status: "paid")
    MlOrder.create!(order_id: id, ml_account: account, status: status, date_created: date, total_amount: price, shipping_id: 700 + id,
                    buyer_nickname: "C#{id}", shipment: { "logistic_type" => "fulfillment", "seller_cost" => shipping, "status" => "delivered" },
                    payload: { "payments" => [ { "transaction_amount" => price, "total_paid_amount" => price, "transaction_amount_refunded" => refunded } ] })
    MlOrderItem.create!(order_id: id, item_id: "MLB#{id}", sku: "SKU-#{id}", title: "Produto #{id}", quantity: 1, unit_price: price, sale_fee: fee)
    create(:olist_product, company: company, sku: "SKU-#{id}", cost_price: 40, status: "A", kind: "S")
  end

  def charge(detail_id, type, sub, amount, at, order_id: nil, label: "x")
    MlBillingCharge.create!(ml_account: account, detail_id: detail_id, period_key: "2026-11-01", detail_type: type, detail_sub_type: sub,
                            transaction_detail: label, amount: amount, order_id: order_id, charged_at: at)
  end

  before do
    today = zone.now.change(hour: 12)
    # hoje: 2 vendas de 100 (custo 40, tarifa 15, frete 10) · ontem: 1 venda de 100 + 1 cancelada
    order(1, today, price: 100, fee: 15, shipping: 10)
    order(2, today, price: 100, fee: 15, shipping: 10, refunded: 20)
    order(3, today - 1.day, price: 100, fee: 15, shipping: 10)
    order(4, today - 1.day, price: 100, fee: 15, shipping: 10, status: "cancelled")
    MlAdDailyMetric.create!(ml_account: account, campaign_id: 1, date: zone.today, cost: 12)
    MlAdDailyMetric.create!(ml_account: account, campaign_id: 1, date: zone.today - 1, cost: 6)
    charge(1, "CHARGE", "CFWA", 3.0, today, label: "Tarifa pelo serviço de armazenamento Full")
    charge(2, "CHARGE", "CVVML", 14.0, today, order_id: 1, label: "Custo por vender no Mercado Livre")
    charge(3, "BONUS", "BVVML", 15.0, today, order_id: 4, label: "Cancelamento do Custo por vender") # venda cancelada: não é crédito
    charge(4, "BONUS", "BFFE", 4.0, today, order_id: 2, label: "Cancelamento da tarifa de envio") # venda ativa: crédito
    charge(5, "CHARGE", "CFONPN", 9.0, today, order_id: 1, label: "Taxa de parcelamento") # neutra
    charge(6, "CHARGE", "PADS", 11.0, today, label: "Tarifa por campanha de publicidade de Product Ads")
  end

  it "monta o DRE de hoje comparado com ontem, com indicadores, saúde, gráficos, extrato e conciliação" do
    get "/api/finance", params: { account_id: account.id, period: "today" }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(json["period"]).to include("previous_label" => "ontem")
    lines = json["statement"].to_h { |l| [ l["key"], l ] }
    expect(lines["revenue"]).to include("value" => 200.0, "previous" => 100.0, "delta_pct" => 100.0)
    expect(lines["refunds"]["value"]).to eq(20.0)
    expect(lines["net_revenue"]["value"]).to eq(180.0)
    expect(lines["cogs"]["value"]).to eq(80.0)
    expect(lines["gross_profit"]["value"]).to eq(100.0)
    expect(lines["fee"]["value"]).to eq(30.0)        # por venda (base Lunna)
    expect(lines["shipping"]["value"]).to eq(20.0)
    expect(lines["tax"]["value"]).to eq(20.0)
    expect(lines["fixed"]["value"]).to eq(4.0)
    expect(lines["full"]["value"]).to eq(3.0)
    expect(lines["credits"]["value"]).to eq(4.0)     # só a bonificação da venda ativa
    expect(lines["operating"]["value"]).to eq(27.0)  # 100 − 30 − 20 − 20 − 4 − 0 − 3 − 0 + 4
    expect(lines["ads"]["value"]).to eq(12.0)
    expect(lines["net"]["value"]).to eq(15.0)
    expect(json["kpis"]["net_margin"]).to include("value" => 7.5)
    expect(json["health"].find { |h| h["key"] == "margin" }).to include("tone" => "warn") # 7,5% abaixo da mínima de 9%
    expect(json["charts"]["daily"].size).to eq(1)
    expect(json["charts"]["daily"].first).to include("revenue" => 200.0, "previous_revenue" => 100.0, "profit" => 200.0 - 80 - 30 - 20 - 20 - 4 - 12)
    expect(json["statement_ml"].find { |g| g["group"] == "parcelamento" }).to include("neutral" => true, "net" => 9.0)
    # conciliação pelas mesmas vendas: a venda 2 ainda não foi cobrada (fica fora); a venda 1 foi cobrada 14 contra 15 do Lunna
    expect(json["reconciliation"].find { |r| r["key"] == "fee" }).to include("lunna" => 15.0, "extrato" => 14.0, "diff" => -1.0, "pending" => 1, "different" => 1)
    expect(json["reconciliation"].find { |r| r["key"] == "ads" }).to include("lunna" => 12.0, "extrato" => 0.0) # PADS de hoje só entra amanhã

    get "/api/finance", params: { account_id: account.id, period: "today", basis: "extrato" }, headers: auth_headers(member)
    lines = json["statement"].to_h { |l| [ l["key"], l ] }
    expect(lines["fee"]["value"]).to eq(14.0)
    expect(lines["ads"]["value"]).to eq(11.0)
    expect(lines["shipping"]["value"]).to eq(-4.0) # só a bonificação do frete no extrato
  end

  it "mês atual compara com os mesmos dias do mês anterior; mês fechado, com o mês anterior inteiro" do
    month = zone.today.strftime("%Y-%m")
    get "/api/finance", params: { account_id: account.id, month: month }, headers: auth_headers(member)
    prev = Date.strptime(month, "%Y-%m").prev_month
    expect(json["period"]["previous_from"]).to start_with(prev.iso8601)
    expect(json["period"]["previous_to"]).to start_with([ prev + (zone.today.day - 1), prev.end_of_month ].min.iso8601)

    get "/api/finance", params: { account_id: account.id, period: "mtd" }, headers: auth_headers(member)
    expect(json["period"]["previous_from"]).to start_with(prev.iso8601)

    closed = zone.today.prev_month.strftime("%Y-%m")
    get "/api/finance", params: { account_id: account.id, month: closed }, headers: auth_headers(member)
    if json["months"].any? { |m| m["value"] == closed }
      before = Date.strptime(closed, "%Y-%m").prev_month
      expect(json["period"]["previous_to"]).to start_with(before.end_of_month.iso8601)
    end
  end

  it "lançamentos manuais entram no DRE e nas abas Receita e Despesas (escrita só admin)" do
    admin = create(:user, :admin, company: company)
    post "/api/finance/entries", params: { account_id: account.id, entry_type: "despesa", date: zone.today.iso8601, category: "Embalagens e insumos", description: "Caixas", amount: 30 },
                                 headers: auth_headers(member), as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/finance/entries", params: { account_id: account.id, entry_type: "despesa", date: zone.today.iso8601, category: "Embalagens e insumos", description: "Caixas", amount: 30 },
                                 headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    post "/api/finance/entries", params: { account_id: account.id, entry_type: "receita", date: zone.today.iso8601, category: "Rendimentos", description: "Mercado Pago", amount: 5 },
                                 headers: auth_headers(admin), as: :json
    id = json["id"]

    get "/api/finance", params: { account_id: account.id, period: "today" }, headers: auth_headers(member)
    lines = json["statement"].to_h { |l| [ l["key"], l ] }
    expect(lines["other_income"]["value"]).to eq(5.0)
    expect(lines["other_expenses"]["value"]).to eq(30.0)
    expect(lines["net"]["value"]).to eq(15.0 + 5 - 30)
    expect(json["revenue"]["entries"].size).to eq(1)
    expect(json["revenue"]["by_logistic"].first).to include("label" => "Full", "value" => 200.0, "previous" => 100.0)
    expect(json["revenue"]["by_product"].size).to eq(2)
    expect(json["expenses"]["items"].find { |i| i["key"] == "other_expenses" }).to include("value" => 30.0)
    expect(json["expenses"]["entries"].first).to include("description" => "Caixas")

    patch "/api/finance/entries/#{id}", params: { account_id: account.id, amount: 7 }, headers: auth_headers(admin), as: :json
    expect(json["amount"]).to eq(7.0)
    get "/api/finance/entries", params: { account_id: account.id, entry_type: "receita" }, headers: auth_headers(member)
    expect(json["entries"].map { |e| e["amount"] }).to eq([ 7.0 ])
    delete "/api/finance/entries/#{id}", params: { account_id: account.id }, headers: auth_headers(admin)
    expect(response).to have_http_status(:no_content)
  end

  it "concilia os repasses: previsto x faturado x pagamento do Mercado Pago x crédito na conta" do
    pay = lambda do |id, order_id, net, coupon: 0, release: nil|
      release ||= zone.now - 1.hour
      MpPayment.create!(ml_account: account, payment_id: id, order_id: order_id, status: "approved", transaction_amount: 100, net_received: net,
                        ml_fee: 14, mp_fee: 1, shipping_fee: 10, coupon_amount: coupon, date_created: zone.now, date_approved: zone.now,
                        money_release_date: release, money_release_status: release.past? ? "released" : "pending")
    end
    pay.(901, 1, 75)                                          # venda 1: conferida e creditada
    pay.(902, 2, 71, coupon: 4, release: zone.now + 5.days)   # venda 2: cupom do vendedor, ainda a liberar
    line = lambda do |key, desc, credit, debit, balance, source: nil|
      MpReleaseLine.create!(ml_account: account, file_name: "r.csv", line_key: key, record_type: "release", description: desc, date: zone.now.beginning_of_day + 1.second,
                            net_credit: credit, net_debit: debit, balance: balance, source_id: source)
    end
    line.("a", "payment", 75, 0, 575, source: 901)
    line.("b", "payout", 0, 500, 75)
    line.("c", "reserve_for_dispute", 0, 20, 55)

    get "/api/finance/repasses", params: { account_id: account.id, period: "today" }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(json["totals"]).to include("sales" => 2, "expected" => 150.0, "mp_net" => 146.0, "credited" => 75.0, "coupon" => 4.0, "to_release" => 71.0)
    expect(json["by_status"].to_h { |s| [ s["key"], s["count"] ] }).to eq("conferido" => 1, "cupom" => 1)
    expect(json["by_credit"].to_h { |s| [ s["key"], s["count"] ] }).to eq("creditado" => 1, "a_liberar" => 1)
    expect(json["divergent"].map { |s| s["order_ids"] }).to eq([ [ 2 ] ]) # só a venda com cupom fica na lista
    legs = json["legs"].to_h { |l| [ l["key"], l ] }
    expect(legs["fee"]).to include("lunna" => 15.0, "billed" => 14.0, "mp" => 15.0, "sales" => 1) # só a venda já faturada entra nas pernas
    expect(legs["coupon"]).to include("lunna" => 0.0, "mp" => 0.0)
    acc = json["account"]
    expect(acc).to include("credits" => 75.0, "debits" => 520.0, "closing" => 55.0)
    expect(acc["rows"].map { |r| r["label"] }).to include("Saques / transferências", "Liberação de vendas")
    expect(acc["reserves"]).to eq([ { "key" => "reserve_for_dispute", "label" => "Reservas por reclamação", "amount" => -20.0 } ])
  end
end
