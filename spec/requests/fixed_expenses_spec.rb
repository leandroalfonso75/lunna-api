require "rails_helper"

RSpec.describe "/api/finance/fixed_expenses", type: :request do
  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 3) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company) }
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:last_month) { zone.today.prev_month.beginning_of_month }
  let(:key) { last_month.strftime("%Y-%m") }

  def sale(id, at:, price: 100.0, qty: 2)
    MlOrder.create!(order_id: id, ml_account: account, status: "paid", date_created: at, total_amount: price * qty, paid_amount: price * qty,
      buyer_nickname: "C#{id}", payload: { "payments" => [ { "id" => 1, "status" => "approved" } ] })
    MlOrderItem.create!(order_id: id, item_id: "MLB1", sku: "SKU-A", title: "Produto", quantity: qty, unit_price: price, sale_fee: 15.0)
  end

  it "lança, lista, copia e exclui; só admin escreve" do
    post "/api/finance/fixed_expenses", params: { month: key, category: "Aluguel", amount: 10 }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    post "/api/finance/fixed_expenses", params: { month: key, category: "Aluguel", description: "Galpão", amount: 6 }, headers: auth_headers(admin)
    expect(response).to have_http_status(:created)
    post "/api/finance/fixed_expenses", params: { month: key, category: "Salários", amount: 4 }, headers: auth_headers(admin)
    post "/api/finance/fixed_expenses", params: { month: key, category: "Salários", amount: 0 }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)

    sale(1, at: zone.local(last_month.year, last_month.month, 10, 12))
    get "/api/finance/fixed_expenses", params: { month: key }, headers: auth_headers(member)
    expect(json["entries"].map { |e| e["category"] }).to eq(%w[Aluguel Salários])
    # faturamento 200, despesas 10 => 5%, mês fechado: vale para as vendas
    expect(json["summary"]).to include("month" => key, "revenue" => 200.0, "total" => 10.0, "pct" => 5.0, "applied_pct" => 5.0, "default_pct" => 3.0, "state" => "aplicado")
    expect(json["months"].map { |m| m["month"] }).to eq([ key ])

    current = zone.today.strftime("%Y-%m")
    post "/api/finance/fixed_expenses/copy", params: { month: current }, headers: auth_headers(admin)
    expect(response).to have_http_status(:created)
    get "/api/finance/fixed_expenses", params: { month: current }, headers: auth_headers(member)
    expect(json["entries"].size).to eq(2)
    expect(json["summary"]).to include("state" => "mes_corrente", "applied_pct" => 3.0) # mês corrente segue o padrão

    delete "/api/finance/fixed_expenses/#{FixedExpense.first.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:no_content)
  end

  it "recalcula as despesas operacionais das vendas do mês fechado em Vendas e no DRE; mês corrente e mês sem lançamento usam o padrão" do
    create(:olist_product, company: company, sku: "SKU-A", cost_price: 40, status: "A", kind: "S")
    sale(1, at: zone.local(last_month.year, last_month.month, 10, 12))
    sale(2, at: zone.now.beginning_of_month + 1.hour)

    get "/api/sales", params: { account_id: account.id, month: key }, headers: auth_headers(member)
    expect(json["sales"].first["economics"]).to include("fixed_expenses" => 6.0, "fixed_expenses_pct" => 3.0) # sem lançamento: 3%

    FixedExpense.create!(company: company, month: last_month, category: "Aluguel", amount: 10)
    FixedExpense.create!(company: company, month: zone.today.beginning_of_month, category: "Aluguel", amount: 100)

    get "/api/sales", params: { account_id: account.id, month: key }, headers: auth_headers(member)
    eco = json["sales"].first["economics"]
    # receita 200; custo 80; tarifa 30; fixas 10 (5% = 10 ÷ 200); imposto 20 => 60
    expect(eco).to include("fixed_expenses" => 10.0, "fixed_expenses_pct" => 5.0, "net_profit" => 60.0)

    get "/api/sales", params: { account_id: account.id, month: zone.today.strftime("%Y-%m") }, headers: auth_headers(member)
    expect(json["sales"].first["economics"]).to include("fixed_expenses" => 6.0, "fixed_expenses_pct" => 3.0) # mês corrente: padrão

    get "/api/finance", params: { account_id: account.id, month: key }, headers: auth_headers(member)
    line = json["statement"].find { |l| l["key"] == "fixed" }
    expect(line["value"]).to eq(10.0)
    expect(line["label"]).to include("5.0% da receita")
  end
end
