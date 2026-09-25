require "rails_helper"

RSpec.describe Abc::PriceSuggestion do
  def fake_economics(fee: 5.0, shipping: 2.0)
    Abc::Economics::Result.new(unit: { fee: fee, shipping: shipping }, month: {})
  end

  describe "kind" do
    it "loading quando não há price_ref e os detalhes ainda não carregaram" do
      metric = build_metric(price: 100)
      item = build_item(price_ref: nil, details_checked_at: nil)

      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: abc_params)

      expect(result[:kind]).to eq("loading")
    end

    it "none quando os detalhes carregaram mas não há preço sugerido válido" do
      metric = build_metric(price: 100)
      item = build_item(price_ref: nil, details_checked_at: Time.current)

      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: abc_params)

      expect(result[:kind]).to eq("none")
    end

    it "none quando o sugerido veio zerado" do
      metric = build_metric(price: 100)
      item = build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 0 }, details_checked_at: Time.current)

      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: abc_params)

      expect(result[:kind]).to eq("none")
    end

    it "diferença de 0,49% -> aligned" do
      metric = build_metric(price: 100)
      item = build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 100.49 })

      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: abc_params)

      expect(result[:kind]).to eq("aligned")
      expect(result[:message]).to eq("alinhado à referência")
    end

    it "diferença de 0,5% -> suggestion" do
      metric = build_metric(price: 100)
      item = build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 100.5 })

      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: abc_params)

      expect(result[:kind]).to eq("suggestion")
    end
  end

  # Preço atual 90 e sugerido 100: diferença de 11%, então é `suggestion` (com 100 = 100
  # seria "alinhado" e a mensagem seria a de alinhamento).
  describe "margem no preço sugerido (com custo)" do
    let(:params) { abc_params(tax_pct: 0, min_margin_pct: 9) }
    let(:metric) { build_metric(price: 90) }
    let(:item) { build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 100 }, fee_at_ref: 0, ship_at_ref: 0) }

    it "margem exatamente 9% -> low false, sem aviso" do
      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: 91, params: params)

      expect(result[:margin_pct]).to eq(9.0)
      expect(result[:low]).to eq(false)
      expect(result[:message]).to be_nil
    end

    it "margem 8,99% -> low true, com aviso" do
      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: 91.01, params: params)

      expect(result[:low]).to eq(true)
      expect(result[:message]).to eq("Abaixo da margem mínima")
    end
  end

  describe "custo máximo (sem custo)" do
    it "exatamente 0 -> aviso de margem consumida" do
      params = abc_params(tax_pct: 0, min_margin_pct: 10)
      metric = build_metric(price: 90)
      item = build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 100 }, fee_at_ref: 90, ship_at_ref: 0)

      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: params)

      expect(result[:max_cost]).to eq(0.0)
      expect(result[:message]).to eq("tarifa, frete e imposto já consomem a margem mínima")
    end

    it "positivo -> sem aviso" do
      params = abc_params(tax_pct: 0, min_margin_pct: 10)
      metric = build_metric(price: 90)
      item = build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 100 }, fee_at_ref: 10, ship_at_ref: 0)

      result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: params)

      expect(result[:max_cost]).to eq(80.0)
      expect(result[:message]).to be_nil
    end
  end

  it "status_text traduz o status do ML" do
    metric = build_metric(price: 90)
    item = build_item(price_ref: { "status" => "with_benchmark_highest", "suggested" => 90 })

    result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: abc_params)

    expect(result[:status_text]).to eq("acima do preço de todos os concorrentes comparados")
  end

  it "competitors traz até 5 do graph, só preço e título" do
    graph = (1..7).map { |i| { "p" => i.to_f, "t" => "Concorrente #{i}", "s" => i * 10 } }
    metric = build_metric(price: 90)
    item = build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 90, "graph" => graph })

    result = described_class.call(item: item, metric: metric, economics: fake_economics, cost: nil, params: abc_params)

    expect(result[:competitors].size).to eq(5)
    expect(result[:competitors].first).to eq({ price: 1.0, title: "Concorrente 1" })
  end

  it "fallback de tarifa/frete no sugerido usa a base atual quando fee_at_ref/ship_at_ref faltam" do
    metric = build_metric(price: 100)
    item = build_item(price_ref: { "status" => "no_benchmark_ok", "suggested" => 200 }, fee_at_ref: nil, ship_at_ref: nil)

    result = described_class.call(item: item, metric: metric, economics: fake_economics(fee: 5.0, shipping: 2.0), cost: nil, params: abc_params(tax_pct: 0, min_margin_pct: 0))

    expect(result[:fee]).to eq(10.0) # 5.0 * (200/100)
    expect(result[:shipping]).to eq(2.0)
  end
end
