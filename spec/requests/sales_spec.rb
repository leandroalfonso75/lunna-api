require "rails_helper"

RSpec.describe "/api/sales", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 5) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company) }

  def sale(id, status: "paid", at: 2.days.ago, shipment: nil, lines: [ [ "MLB1", "SKU-A", 2, 100.0, 15.0 ] ])
    order = MlOrder.create!(order_id: id, ml_account: account, status: status, date_created: at, total_amount: 200,
      paid_amount: 200, shipping_id: shipment ? id + 1 : nil, shipment: shipment, shipment_synced_at: shipment ? Time.current : nil,
      buyer_nickname: "COMPRADOR#{id}", payload: { "payments" => [ { "id" => 1, "status" => "approved", "payment_type" => "credit_card" } ],
                                                    "order_items" => [ { "item" => { "id" => "MLB1", "title" => "Produto A", "seller_sku" => "SKU-A" }, "quantity" => 2, "unit_price" => 100.0, "sale_fee" => 15.0 } ] })
    lines.each do |item_id, sku, qty, price, fee|
      MlOrderItem.create!(order_id: id, item_id: item_id, sku: sku, title: "Produto #{sku}", quantity: qty, unit_price: price, sale_fee: fee)
    end
    order
  end

  def with_cost(sku, value)
    create(:olist_product, company: company, sku: sku, cost_price: value, status: "A", kind: "S")
  end

  it "calcula o lucro líquido da venda: receita − custo − tarifa − frete − despesas fixas − imposto" do
    with_cost("SKU-A", 40)
    sale(1, shipment: { "status" => "delivered", "logistic_type" => "fulfillment", "seller_cost" => 20.0 })

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    economics = json["sales"].first["economics"]
    # receita 200; custo 80; tarifa 30; frete 20; fixas 10 (5%); imposto 20 (10%) => 40
    expect(economics).to include("revenue" => 200.0, "cost" => 80.0, "fee" => 30.0, "shipping_cost" => 20.0,
      "fixed_expenses" => 10.0, "tax" => 20.0, "net_profit" => 40.0, "net_profit_pct" => 20.0)
    expect(json["summary"]).to include("orders" => 1, "units" => 2, "revenue" => 200.0, "net_profit" => 40.0, "orders_without_cost" => 0)
    expect(numeric_strings(json)).to be_empty
  end

  it "carrinho: o frete do vendedor do envio é dividido entre as vendas do mesmo envio, por unidade" do
    with_cost("SKU-A", 10)
    with_cost("SKU-B", 10)
    shipment = { "status" => "delivered", "logistic_type" => "self_service", "seller_cost" => 30.0 }
    sale(1, shipment: shipment, lines: [ [ "MLB1", "SKU-A", 1, 100.0, 10.0 ] ])
    sale(3, shipment: shipment.merge("id" => 1), lines: [ [ "MLB2", "SKU-B", 2, 50.0, 5.0 ] ])
    MlOrder.where(order_id: [ 1, 3 ]).update_all(shipping_id: 777, pack_id: 555)
    sale(5, status: "cancelled", shipment: shipment, lines: [ [ "MLB3", "SKU-A", 5, 10.0, 1.0 ] ])
    MlOrder.where(order_id: 5).update_all(shipping_id: 777)

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

    by_id = json["sales"].to_h { |s| [ s["order_id"], s ] }
    expect(by_id[1]["economics"]["shipping_cost"]).to eq(10.0) # 1 de 3 unidades
    expect(by_id[3]["economics"]["shipping_cost"]).to eq(20.0) # 2 de 3 unidades
    expect(by_id[1]["shipping"]).to include("seller_cost" => 30.0, "seller_cost_share" => 10.0, "shared_with" => [ 3 ])
    expect(json["summary"]["shipping_cost"]).to eq(30.0) # o frete do envio conta uma vez só
  end

  it "envio sem carrinho mantém o frete inteiro na venda" do
    sale(1, shipment: { "status" => "delivered", "seller_cost" => 21.1 })

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["sales"].first["economics"]["shipping_cost"]).to eq(21.1)
    expect(json["sales"].first["shipping"]["shared_with"]).to eq([])
  end

  it "venda cancelada mostra quem cancelou e o motivo da reclamação" do
    order = sale(1, status: "cancelled")
    order.update_columns(payload: order.payload.merge("cancel_detail" => { "code" => "buyer_cancel_express", "requested_by" => "buyer", "date" => "2026-10-26T20:18:21.000-04:00" }),
      claims: [ { "id" => 9, "type" => "cancel_purchase", "status" => "closed", "reason" => "Me arrependi da compra", "opened_by" => "buyer",
                  "resolution" => { "reason" => "coverage_decision", "benefited" => [ "complainant" ], "applied_coverage" => true } } ])

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

    issue = json["sales"].first["issue"]
    expect(issue["label"]).to eq("Comprador cancelou antes do envio · Me arrependi da compra")
    expect(issue["cancellation"]).to include("requested_by" => "comprador")
    expect(issue["claims"].first["resolution"]).to include("label" => "decisão do Mercado Livre", "benefited" => "a favor do comprador", "coverage" => true)

    get "/api/sales/1", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["issue"]["label"]).to eq("Comprador cancelou antes do envio · Me arrependi da compra")
  end

  it "venda paga com reclamação aberta e devolução mostra o andamento" do
    sale(1).update_columns(claims: [ { "id" => 9, "type" => "mediations", "status" => "opened", "stage" => "claim", "reason" => "Recebi outro tipo de produto",
                                       "return" => { "status" => "shipped", "status_money" => "retained", "subtype" => "return_total" } } ])

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

    issue = json["sales"].first["issue"]
    expect(issue).to include("tone" => "bad", "label" => "Reclamação aberta · Recebi outro tipo de produto · devolução a caminho do vendedor")
    expect(issue["claims"].first["return"]).to include("money" => "dinheiro retido")
    expect(json["sales"].first["economics"]).to be_present
  end

  describe "custo de Ads e lucro pós Ads" do
    let(:day) { 2.days.ago.to_date }
    let(:at) { Time.zone.local(day.year, day.month, day.day, 14) }

    def spend(item_id, date, cost)
      MlAdItemDaily.create!(ml_account: account, item_id: item_id, date: date, cost: cost)
    end

    def day_read(date, fetched_at)
      MlAdDaySync.create!(ml_account: account, date: date, fetched_at: fetched_at)
    end

    before do
      with_cost("SKU-A", 40)
      MlAdItem.create!(ml_account_id: account.id, item_id: "MLB1", campaign_id: 1, synced_at: Time.current)
    end

    it "divide o gasto do anúncio no período entre as unidades vendidas dele no período" do
      spend("MLB1", day, 30.0)
      spend("MLB1", day - 3, 15.0) # dia sem venda: entra no rateio do período
      day_read(day, Time.current)
      sale(1, at: at)                                                     # 2 unidades
      sale(2, at: at + 1.hour, lines: [ [ "MLB1", "SKU-A", 1, 100.0, 15.0 ] ]) # 1 unidade

      get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

      by_id = json["sales"].to_h { |s| [ s["order_id"], s["economics"] ] }
      expect(by_id[1]).to include("ads_cost" => 30.0, "ads_state" => "apurado", "net_profit" => 60.0, "net_profit_after_ads" => 30.0,
        "net_profit_after_ads_pct" => 15.0)
      expect(by_id[1]["ads_lines"].first).to include("period_cost" => 45.0, "period_units" => 3)
      expect(by_id[2]["ads_cost"]).to eq(15.0)
      expect(json["summary"]).to include("ads_cost" => 45.0, "ads_cost_sales" => 45.0, "ads_unsold" => 0.0, "orders_ads_pending" => 0)
    end

    it "gasto de anúncio que não vendeu no período fica no resumo como Ads sem venda e sai do lucro pós Ads" do
      spend("MLB1", day, 30.0)
      spend("MLB7", day, 12.5) # anúncio sem nenhuma venda no período
      day_read(day, Time.current)
      sale(1, at: at)

      get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["summary"]).to include("ads_cost" => 42.5, "ads_cost_sales" => 30.0, "ads_unsold" => 12.5,
        "net_profit_after_ads" => 17.5)
    end

    it "gasto das campanhas que o ML não detalha por anúncio também entra em Ads sem venda (total igual ao da seção Ads)" do
      spend("MLB1", day, 30.0)
      MlAdDailyMetric.create!(ml_account_id: account.id, campaign_id: 1, date: day, cost: 30.21)
      day_read(day, Time.current)
      sale(1, at: at)

      get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["summary"]["ads_unsold"]).to be_within(0.001).of(0.21)
      expect(json["summary"]["ads_cost"]).to be_within(0.001).of(30.21)
    end

    it "com filtro na tela, o gasto sem venda fica de fora do resumo" do
      spend("MLB7", day, 12.5)
      day_read(day, Time.current)
      sale(1, at: at)

      get "/api/sales", params: { account_id: account.id, q: "MLB1" }, headers: auth_headers(member)

      expect(json["summary"]).to include("ads_unsold" => nil, "ads_cost" => 0.0)
    end

    it "o detalhe usa o mesmo período da lista no rateio" do
      spend("MLB1", day, 30.0)
      spend("MLB1", 20.days.ago.to_date, 60.0)
      day_read(day, Time.current)
      sale(1, at: at)

      get "/api/sales/1", params: { account_id: account.id, period: "7d" }, headers: auth_headers(member)
      expect(json["economics"]["ads_cost"]).to eq(30.0)

      get "/api/sales/1", params: { account_id: account.id, period: "30d" }, headers: auth_headers(member)
      expect(json["economics"]["ads_cost"]).to eq(90.0)
    end

    it "dia ainda não fechado na leitura de Ads deixa a venda pendente (refeita na próxima leitura)" do
      spend("MLB1", day, 30.0)
      day_read(day, at + 2.hours) # lido no mesmo dia: ainda pode mudar
      sale(1, at: at)

      get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["sales"].first["economics"]).to include("ads_state" => "pendente", "ads_cost" => 30.0)
      expect(json["summary"]["orders_ads_pending"]).to eq(1)
    end

    it "dia ainda não lido também fica pendente" do
      sale(1, at: at)

      get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["sales"].first["economics"]).to include("ads_state" => "pendente", "ads_cost" => 0.0)
    end

    it "anúncio fora de Ads não tem custo de Ads e o lucro pós Ads é o próprio lucro" do
      sale(1, at: at, lines: [ [ "MLB9", "SKU-A", 2, 100.0, 15.0 ] ])

      get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["sales"].first["economics"]).to include("ads_state" => "sem_ads", "ads_cost" => 0.0, "net_profit_after_ads" => 60.0)
    end

    it "ordena pelo lucro pós Ads" do
      spend("MLB1", day, 30.0)
      day_read(day, Time.current)
      sale(1, at: at)
      sale(2, at: at, lines: [ [ "MLB9", "SKU-A", 2, 100.0, 15.0 ] ])

      get "/api/sales", params: { account_id: account.id, sort: "profit_after_ads", dir: "desc" }, headers: auth_headers(member)

      expect(json["sales"].map { |s| s["order_id"] }).to eq([ 2, 1 ])
    end
  end

  it "sem custo em algum item, o lucro da venda não é calculado e ela é contada à parte" do
    sale(1)

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["sales"].first["economics"]["net_profit"]).to be_nil
    expect(json["summary"]).to include("orders_without_cost" => 1, "net_profit" => 0, "net_profit_pct" => nil)
  end

  it "venda cancelada fica fora dos totais e sem economia" do
    with_cost("SKU-A", 40)
    sale(1)
    sale(2, status: "cancelled")

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["summary"]).to include("orders" => 1, "cancelled" => 1)
    expect(json["sales"].find { |s| s["order_id"] == 2 }["economics"]).to be_nil
  end

  it "filtra por período, situação, envio e logística, com contagens" do
    sale(1, at: 2.days.ago, shipment: { "status" => "delivered", "logistic_type" => "fulfillment" })
    sale(2, at: 3.days.ago, shipment: { "status" => "shipped", "logistic_type" => "self_service" })
    sale(3, at: 60.days.ago, shipment: { "status" => "delivered", "logistic_type" => "fulfillment" })
    sale(4, at: 1.day.ago, status: "cancelled")

    get "/api/sales", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 4, 1, 2 ]) # 30 dias por padrão, mais nova primeiro
    expect(json["counts"]["shipping"]).to include("delivered" => 1, "transit" => 1)
    expect(json["counts"]["logistic"]).to include("full" => 1, "flex" => 1)

    get "/api/sales", params: { account_id: account.id, period: "90d" }, headers: auth_headers(member)
    expect(json["total"]).to eq(4)

    get "/api/sales", params: { account_id: account.id, status: "cancelled" }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 4 ])

    get "/api/sales", params: { account_id: account.id, shipping: "transit" }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 2 ])

    get "/api/sales", params: { account_id: account.id, logistic: "full" }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 1 ])
  end

  it "hoje e ontem mostram só as vendas do dia" do
    sale(1, at: Time.current.beginning_of_day + 1.minute)
    sale(2, at: 1.day.ago.beginning_of_day + 2.hours)
    sale(3, at: 2.days.ago)

    get "/api/sales", params: { account_id: account.id, period: "today" }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 1 ])
    expect(json["period"]["preset"]).to eq("today")
    expect(json["daily"].size).to eq(1)

    get "/api/sales", params: { account_id: account.id, period: "yesterday" }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 2 ])
    expect(json["daily"].size).to eq(1)
  end

  it "aceita intervalo de datas e limita a 92 dias" do
    sale(1, at: 10.days.ago)
    sale(2, at: 120.days.ago)

    get "/api/sales", params: { account_id: account.id, from: 200.days.ago.to_date.iso8601, to: Date.current.iso8601 },
      headers: auth_headers(member)

    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 1 ])
  end

  it "busca por número, comprador, SKU e título" do
    sale(11, lines: [ [ "MLB1", "ABC-1", 1, 50.0, 5.0 ] ])
    sale(12, lines: [ [ "MLB2", "XYZ-9", 1, 50.0, 5.0 ] ])

    { "12" => [ 12 ], "COMPRADOR11" => [ 11 ], "xyz" => [ 12 ], "produto abc" => [ 11 ] }.each do |q, ids|
      get "/api/sales", params: { account_id: account.id, q: q }, headers: auth_headers(member)
      expect(json["sales"].map { |s| s["order_id"] }).to eq(ids), "busca #{q}"
    end
  end

  it "ordena por lucro % (sem lucro vai para o fim) e pagina" do
    with_cost("SKU-A", 40)
    with_cost("SKU-B", 90)
    sale(1)
    sale(2, lines: [ [ "MLB2", "SKU-B", 2, 100.0, 15.0 ] ])
    sale(3, lines: [ [ "MLB3", "SEM-CUSTO", 1, 10.0, 1.0 ] ])

    get "/api/sales", params: { account_id: account.id, sort: "profit_pct", dir: "desc", per_page: 25 }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 1, 2, 3 ])

    get "/api/sales", params: { account_id: account.id, sort: "profit_pct", dir: "asc" }, headers: auth_headers(member)
    expect(json["sales"].map { |s| s["order_id"] }).to eq([ 2, 1, 3 ])
  end

  it "o detalhe traz pagamentos, itens e envio" do
    sale(1, shipment: { "status" => "delivered", "tracking_number" => "T1", "seller_cost" => 5.0 })

    get "/api/sales/1", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(json["payments"].first).to include("status" => "approved")
    expect(json["items_detail"].first).to include("item_id" => "MLB1", "sku" => "SKU-A")
    expect(json["shipping"]).to include("label" => "Entregue", "tracking_number" => "T1")
  end

  it "venda de outra conta é 404 e conta de outra empresa também" do
    other = create(:ml_account)
    get "/api/sales/999", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:not_found)

    get "/api/sales", params: { account_id: other.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:not_found)
  end

  it "só administrador baixa os 3 meses de novo (job na fila)" do
    post "/api/sales/sync", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    expect do
      post "/api/sales/sync", params: { account_id: account.id }, headers: auth_headers(admin)
    end.to have_enqueued_job(Ml::SalesBackfillJob).with(account.id)
    expect(response).to have_http_status(:accepted)
  end

  it "exige login" do
    get "/api/sales", params: { account_id: account.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it "período mês até hoje: do dia 1º do mês corrente até hoje" do
    travel_to(Time.find_zone("America/Sao_Paulo").parse("2026-10-30 15:00")) do
      get "/api/sales", params: { account_id: account.id, period: "mtd" }, headers: auth_headers(member)
    end

    expect(response).to have_http_status(:ok)
    expect(json["period"]["preset"]).to eq("mtd")
    expect(json["period"]["from"]).to start_with("2026-10-01")
    expect(json["period"]["to"]).to start_with("2026-10-30")
  end
end
