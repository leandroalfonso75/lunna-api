require "rails_helper"

RSpec.describe "/api/stock (seção Estoque)", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }

  def rec(up, sku, **attrs)
    { identifiers: { user_product_id: up, inventory_id: attrs[:inventory] || "INV#{up}", seller_sku: sku },
      product: { tags: [ "is_fulfillment" ] },
      stock: { total_stock: attrs[:stock] || 0, shipping_urgency: attrs[:urgency] || "NO_URGENCY", minimum_distributable_stock: 0 },
      sales: { sales_totals: { period: "30DAYS", gmv: [ { full: 300.0 } ], units_sold: [ { full: 3 } ] },
               sales_history: [ { start_date: "2026-11-07", end_date: "2026-11-13", units_sold: 7, days_out_of_stock: 0 },
                                { start_date: "2026-10-31", end_date: "2026-11-06", units_sold: 0, days_out_of_stock: 7 } ] },
      recommendation: attrs[:suggest] ? { recommendation_type: "REPLENISH", suggested_quantity: { type: "exact", value: attrs[:suggest] }, replenishment_deadline: "THIS_WEEK", replenishment_frequency: 4 }
                                      : { recommendation_type: "NO_REPLENISHMENT", suggested_quantity: nil, replenishment_deadline: "NOT_REPLENISHMENT_NEEDED" },
      eligibility_benefits: [] }
  end

  it "lê as recomendações do Full e mostra o que repor, quanto dá para enviar do Olist e a receita perdida por falta" do
    stub_request(:get, "#{ml}/marketplace/fbm/sellers/430/user-products/replenishment").with(query: hash_including(country: "BR"))
      .to_return(status: 200, body: { results: [ rec("MLBU1", "SEC-1", urgency: "URGENT", suggest: 24), rec("MLBU2", "BASE-1", stock: 10) ],
                                      paging: { total: 2 } }.to_json)
    create(:ml_item, ml_account: account, item_id: "MLB1", user_product_id: "MLBU1", sku: "SEC-1", title: "Secador", price: 100)
    create(:olist_product, company: company, sku: "SEC-1", description: "Secador", stock_available: 10, cost_price: 40, status: "A", kind: "S")

    Ml::Sync::FullReplenishment.call(Ml::Client.new(access_token: "tok", sleeper: ->(_) { }), account)
    expect(account.ml_full_replenishments.count).to eq(2)

    get "/api/stock/full", params: { account_id: account.id, view: "repor" }, headers: auth_headers(member)
    row = json["rows"].sole
    # 7 unidades em 7 dias com estoque; 7 dias sem estoque => 7 unidades perdidas × R$ 100
    expect(row).to include("sku" => "SEC-1", "title" => "Secador", "urgency" => "URGENT", "suggested" => 24, "olist_available" => 10.0,
                           "can_send" => 10, "to_buy" => 14, "days_out" => 7, "lost_revenue" => 700.0)
    expect(json["summary"]).to include("replenish" => 1, "urgent" => 1, "suggested_units" => 24, "can_send_units" => 10, "to_buy_units" => 14)
  end

  it "depósito: estoque do Olist com valor, vendas (inclusive pelos kits) e cobertura" do
    comp = create(:olist_product, company: company, sku: "SEC-1", description: "Secador", stock_available: 30, cost_price: 40, status: "A", kind: "S")
    create(:olist_product, company: company, sku: "KIT-1", description: "Secador + difusor", kind: "K", status: "A",
                           kit_components: [ { "id" => comp.olist_id, "sku" => "SEC-1", "quantity" => 1 } ])
    MlOrder.create!(order_id: 1, ml_account: account, status: "paid", date_created: 2.days.ago, total_amount: 200)
    MlOrderItem.create!(order_id: 1, item_id: "MLB1", sku: "KIT-1", title: "Kit", quantity: 2, unit_price: 100, sale_fee: 10)
    MlOrderItem.create!(order_id: 1, item_id: "MLB2", sku: "SEC-1", title: "Secador", quantity: 1, unit_price: 90, sale_fee: 9)

    get "/api/stock/depot", params: { account_id: account.id }, headers: auth_headers(member)

    row = json["rows"].sole # o kit não aparece: não tem estoque próprio
    expect(row).to include("sku" => "SEC-1", "olist" => 30.0, "unit_cost" => 40.0, "value_olist" => 1200.0, "sold_30d" => 3, "coverage_days" => 300, "state" => "ok")
    expect(json["summary"]).to include("skus" => 1, "value_olist" => 1200.0)
  end
end
