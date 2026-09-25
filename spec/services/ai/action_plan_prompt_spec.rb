require "rails_helper"

RSpec.describe Ai::ActionPlanPrompt do
  let(:detail) do
    {
      unit: { price: 100.0, full_price: 120.0, fee: 10.0, shipping: 5.0, tax: 11.3, cost: nil },
      month: { revenue: 1000.0, profit: 200.0, profit_is_before_cost: true, margin_pct: 20.0 },
      indicators: { visits: 500, prev_visits: 400, units: 30, prev_units: 20, conversion: 6.0, revenue: 1000.0 },
      listing: { stock: 15, pictures: 8, has_video: true, description_len: 500, quality_score: 85, listing_type_label: "Premium" },
      price: { suggested: 95.0, diff_pct: -5.0, status_text: "acima da referência", margin_pct: nil, max_cost: 12.0, competitors: [] },
      suggestions: [ { priority: 1, area: "estoque", title: "Repor estoque", why: "estoque zerado" } ]
    }
  end

  let(:row) { { title: "Produto X", sku: "SKU1", status_label: "Ativo", curve: "A", group: "up", full: true } }

  let(:context) do
    {
      free_shipping: true, conversion_median: 4.5, tax_pct: 11.3, min_margin_pct: 9.0,
      brand: "Bosch", model: "GSB13", attrs_missing_required: [ "Voltagem" ], attrs_missing_main: [],
      quality_pending: []
    }
  end

  subject(:prompt) { described_class.call(detail, row, context) }

  it "monta as 5 seções numeradas e as instruções de política" do
    expect(prompt[:system]).to include("1. Diagnóstico")
    expect(prompt[:system]).to include("2. Até 5 ações")
    expect(prompt[:system]).to include("3. Título sugerido")
    expect(prompt[:system]).to include("4. Estrutura da descrição")
    expect(prompt[:system]).to include("5. Preço")
    expect(prompt[:system]).to include("60 caracteres")
    expect(prompt[:system]).to include("fundo branco")
    expect(prompt[:system]).to include("sem links")
    expect(prompt[:system]).to include("nunca invente números")
  end

  it "sem custo cadastrado, deixa explícito que o lucro é antes do custo e pede o custo máximo" do
    expect(prompt[:system]).to include("lucro antes do custo")
    expect(prompt[:system]).to include("max_cost")
  end

  it "com custo cadastrado, não menciona lucro antes do custo" do
    detail[:month][:profit_is_before_cost] = false

    expect(prompt[:system]).not_to include("lucro antes do custo")
  end

  it "o user traz todos os campos de dados da SPEC 9" do
    data = JSON.parse(prompt[:user])

    expect(data.values_at(
      "title", "sku", "status", "curve", "group", "price", "full_price", "listing_type", "full", "free_shipping"
    )).to eq([ "Produto X", "SKU1", "Ativo", "A", "up", 100.0, 120.0, "Premium", true, true ])

    expect(data.values_at(
      "stock", "visits_30d", "prev_visits_30d", "units_30d", "prev_units_30d", "conversion_30d", "conversion_median", "revenue_30d"
    )).to eq([ 15, 500, 400, 30, 20, 6.0, 4.5, 1000.0 ])

    expect(data.values_at(
      "fee_per_unit", "shipping_per_unit", "tax_pct", "cost", "min_margin_pct", "profit_month", "profit_is_before_cost"
    )).to eq([ 10.0, 5.0, 11.3, nil, 9.0, 200.0, true ])

    expect(data.values_at(
      "pictures", "has_video", "description_len", "quality_score", "brand", "model"
    )).to eq([ 8, true, 500, 85, "Bosch", "GSB13" ])

    expect(data["attrs_missing_required"]).to eq([ "Voltagem" ])
    expect(data["attrs_missing_main"]).to eq([])
    expect(data["quality_pending"]).to eq([])
    expect(data["price_ref"]).to eq(
      "suggested" => 95.0, "diff_pct" => -5.0, "status_text" => "acima da referência", "margin_pct" => nil, "max_cost" => 12.0, "competitors" => []
    )
    expect(data["suggestions"]).to eq([ { "priority" => 1, "area" => "estoque", "title" => "Repor estoque", "why" => "estoque zerado" } ])
  end
end
