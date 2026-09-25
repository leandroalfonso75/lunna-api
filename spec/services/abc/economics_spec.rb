require "rails_helper"

RSpec.describe Abc::Economics do
  describe "margem mínima (min_margin_pct=9, sem tarifa/frete/imposto pra isolar o limite)" do
    let(:params) { abc_params(tax_pct: 0, min_margin_pct: 9) }
    let(:item) { build_item(fee_now: 0, ship_cost: 0) }
    let(:metric) { build_metric(price: 100, units_30d: 10, revenue_30d: 1000, fees_30d: 0) }

    it "margem exatamente 9% -> ok" do
      result = described_class.call(metric: metric, item: item, cost: 91, params: params)

      expect(result.unit[:margin_pct]).to eq(9.0)
      expect(result.unit[:margin_state]).to eq("ok")
      expect(result.unit[:low_margin]).to eq(false)
    end

    it "margem 8,99% -> bad" do
      result = described_class.call(metric: metric, item: item, cost: 91.01, params: params)

      expect(result.unit[:margin_pct]).to be_within(0.001).of(8.99)
      expect(result.unit[:margin_state]).to eq("bad")
      expect(result.unit[:low_margin]).to eq(true)
    end
  end

  describe "sem custo cadastrado" do
    let(:params) { abc_params(tax_pct: 0, min_margin_pct: 9) }
    let(:item) { build_item(fee_now: 50, ship_cost: 0) }
    let(:metric) { build_metric(price: 100, units_30d: 10, revenue_30d: 0, fees_30d: 0) }

    it "nunca marca low_margin e margin_state fica nil, mesmo com sobra bem abaixo da mínima" do
      result = described_class.call(metric: metric, item: item, cost: nil, params: params)

      expect(result.unit[:low_margin]).to eq(false)
      expect(result.month[:low_margin]).to eq(false)
      expect(result.unit[:margin_state]).to be_nil
      expect(result.month[:margin_state]).to be_nil
      expect(result.unit[:profit_is_before_cost]).to eq(true)
      expect(result.month[:profit_is_before_cost]).to eq(true)
    end
  end

  describe "tarifa por unidade" do
    let(:params) { abc_params(tax_pct: 0) }

    it "usa fee_now quando presente" do
      metric = build_metric(price: 100, units_30d: 10, fees_30d: 999)
      item = build_item(fee_now: 7.5, ship_cost: 0)

      result = described_class.call(metric: metric, item: item, cost: nil, params: params)

      expect(result.unit[:fee]).to eq(7.5)
    end

    it "sem fee_now, cai pro fallback tarifas reais 30d / vendas 30d" do
      metric = build_metric(price: 100, units_30d: 10, fees_30d: 120)
      item = build_item(fee_now: nil, ship_cost: 0)

      result = described_class.call(metric: metric, item: item, cost: nil, params: params)

      expect(result.unit[:fee]).to eq(12.0)
    end

    it "sem fee_now e sem vendas 30d, tarifa fica 0" do
      metric = build_metric(price: 100, units_30d: 0, fees_30d: 0)
      item = build_item(fee_now: nil, ship_cost: 0)

      result = described_class.call(metric: metric, item: item, cost: nil, params: params)

      expect(result.unit[:fee]).to eq(0.0)
    end
  end

  it "profit_state fica bad quando o lucro é negativo, com ou sem custo" do
    metric = build_metric(price: 10, units_30d: 1, revenue_30d: 10, fees_30d: 0)
    item = build_item(fee_now: 50, ship_cost: 0)
    params = abc_params(tax_pct: 0)

    sem_custo = described_class.call(metric: metric, item: item, cost: nil, params: params)
    com_custo = described_class.call(metric: metric, item: item, cost: 1, params: params)

    expect(sem_custo.unit[:profit_state]).to eq("bad")
    expect(com_custo.unit[:profit_state]).to eq("bad")
  end

  it "full_price fica nil quando não há desconto (preço cheio igual ao de venda)" do
    metric = build_metric(price: 120)
    item = build_item(price: 120)

    result = described_class.call(metric: metric, item: item, cost: nil, params: abc_params)

    expect(result.unit[:full_price]).to be_nil
  end

  it "full_price vem do preço cheio do ml_item (não do preço de venda do item_metrics)" do
    metric = build_metric(price: 90)
    item = build_item(price: 120)

    result = described_class.call(metric: metric, item: item, cost: nil, params: abc_params)

    expect(result.unit[:full_price]).to eq(120.0)
  end

  it "mês: tarifas reais quando != 0, senão tarifa/un x vendas 30d" do
    metric = build_metric(price: 100, units_30d: 10, revenue_30d: 1000, fees_30d: 0)
    item = build_item(fee_now: 8, ship_cost: 2)
    params = abc_params(tax_pct: 0)

    result = described_class.call(metric: metric, item: item, cost: nil, params: params)

    expect(result.month[:fees]).to eq(80.0)
    expect(result.month[:shipping]).to eq(20.0)
  end
end
