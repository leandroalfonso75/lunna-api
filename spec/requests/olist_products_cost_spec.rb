require "rails_helper"

RSpec.describe "Custo PEPS nos produtos do Olist", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }

  def find(id) = json["products"].find { |p| p["id"] == id }

  it "mostra o custo PEPS, o valor em estoque e as camadas" do
    create(:olist_product, company: company, olist_id: 1, fifo_unit_cost: 8, fifo_stock_value: 80, fifo_units: 10,
      fifo_units_without_cost: 0, fifo_calculated_at: Time.current, cost_price: 0,
      fifo_layers: [ { "moved_at" => "2026-01-02T13:00:00Z", "quantity" => 10.0, "remaining" => 10.0, "unit_cost" => 8.0 } ])

    get "/api/olist/products", headers: auth_headers(member)

    expect(find(1)["cost"]).to include("available" => true, "fifo_unit" => "8.0", "warning" => false)
    expect(find(1)["cost"]["layers"].first).to include("remaining" => 10.0, "unit_cost" => 8.0)
    expect(find(1)["cost"]["registered"]).to eq("0.0")
  end

  it "aviso quando há unidades em estoque sem custo na entrada" do
    create(:olist_product, company: company, olist_id: 2, fifo_unit_cost: nil, fifo_units_without_cost: 6, fifo_calculated_at: Time.current)

    get "/api/olist/products", headers: auth_headers(member)

    expect(find(2)["cost"]).to include("warning" => true, "fifo_unit" => nil)
    expect(find(2)["cost"]["warning_units"].to_f).to eq(6.0)
  end

  it "informa a diferença entre o histórico e o estoque de hoje (Olist + Full do ML)" do
    create(:olist_product, company: company, olist_id: 5, sku: "GAP", stock_balance: 100, fifo_units: 90, fifo_calculated_at: Time.current)
    create(:olist_product, company: company, olist_id: 6, sku: "OK", stock_balance: 50, fifo_units: 50, fifo_calculated_at: Time.current)

    get "/api/olist/products", headers: auth_headers(member)

    expect(find(5)["cost"]["balance_gap"]).to eq(-10.0)
    expect(find(6)["cost"]["balance_gap"]).to eq(0.0)
  end

  it "produto ainda não calculado vem como indisponível" do
    create(:olist_product, company: company, olist_id: 3)

    get "/api/olist/products", headers: auth_headers(member)

    expect(find(3)["cost"]).to include("available" => false, "warning" => false)
  end

  it "o pai mostra a faixa de custo das variações e o aviso se alguma tiver" do
    create(:olist_product, company: company, olist_id: 10, variation_kind: "P")
    create(:olist_product, company: company, olist_id: 11, variation_kind: "V", parent_olist_id: 10, fifo_unit_cost: 5,
      fifo_stock_value: 50, fifo_units: 10, fifo_calculated_at: Time.current)
    create(:olist_product, company: company, olist_id: 12, variation_kind: "V", parent_olist_id: 10, fifo_unit_cost: 9,
      fifo_stock_value: 18, fifo_units: 2, fifo_units_without_cost: 3, fifo_calculated_at: Time.current)

    get "/api/olist/products", headers: auth_headers(member)

    cost = find(10)["cost"]
    expect(cost["range"]).to eq([ 5.0, 9.0 ])
    expect(cost["warning"]).to be true
    expect(cost["stock_value"].to_f).to eq(68.0)
  end

  it "o estado da leitura de custos aparece em /api/olist (sem permissão no Olist)" do
    create(:olist_connection, company: company, costs_status: "forbidden", costs_checked_at: Time.current)

    get "/api/olist", headers: auth_headers(member)

    expect(json["olist"]["costs"]).to include("status" => "forbidden")
  end
end
