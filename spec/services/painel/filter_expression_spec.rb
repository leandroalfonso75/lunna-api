require "rails_helper"

RSpec.describe Painel::FilterExpression do
  describe ".parse" do
    it "vazio devolve nil" do
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse("   ")).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end

    it "número solto = igual" do
      expect(described_class.parse("10")).to eq(op: "=", value: 10.0)
    end

    it "operadores >, <, >=, <=, =" do
      expect(described_class.parse(">10")).to eq(op: ">", value: 10.0)
      expect(described_class.parse("< 5")).to eq(op: "<", value: 5.0)
      expect(described_class.parse(">= 10")).to eq(op: ">=", value: 10.0)
      expect(described_class.parse("<=10")).to eq(op: "<=", value: 10.0)
      expect(described_class.parse("=0")).to eq(op: "=", value: 0.0)
    end

    it "faixa com -, a e até, extremos em qualquer ordem" do
      expect(described_class.parse("10-50")).to eq(range: [ 10.0, 50.0 ])
      expect(described_class.parse("10 a 50")).to eq(range: [ 10.0, 50.0 ])
      expect(described_class.parse("50 a 10")).to eq(range: [ 10.0, 50.0 ])
      expect(described_class.parse("10 até 50")).to eq(range: [ 10.0, 50.0 ])
    end

    it "negativos: -15 é número, >-5 é operador, -15 a -5 é faixa" do
      expect(described_class.parse("-15")).to eq(op: "=", value: -15.0)
      expect(described_class.parse(">-5")).to eq(op: ">", value: -5.0)
      expect(described_class.parse("-15 a -5")).to eq(range: [ -15.0, -5.0 ])
    end

    it "números BR: milhar com ponto, decimal com vírgula, R$ e % ignorados" do
      expect(described_class.parse("1.234,56")).to eq(op: "=", value: 1234.56)
      expect(described_class.parse("1.234")).to eq(op: "=", value: 1234.0)
      expect(described_class.parse("10.5")).to eq(op: "=", value: 10.5)
      expect(described_class.parse("R$ 1.234,56")).to eq(op: "=", value: 1234.56)
      expect(described_class.parse("15%")).to eq(op: "=", value: 15.0)
    end

    it "expressões inválidas devolvem :invalid" do
      expect(described_class.parse(">")).to eq(:invalid)
      expect(described_class.parse("abc")).to eq(:invalid)
      expect(described_class.parse("10 a")).to eq(:invalid)
      expect(described_class.parse("1,2,3")).to eq(:invalid)
    end
  end

  describe ".apply" do
    let(:account) { create(:ml_account) }

    it "faixa: BETWEEN inclusivo" do
      create(:item_metric, ml_account: account, price: 10)
      create(:item_metric, ml_account: account, price: 50)
      create(:item_metric, ml_account: account, price: 51)

      result = described_class.apply(account.item_metrics, :price, described_class.parse("10-50"))

      expect(result.pluck(:price).map(&:to_f)).to match_array([ 10.0, 50.0 ])
    end

    it "igualdade com tolerância 1e-9" do
      create(:item_metric, ml_account: account, price: 10.0)

      result = described_class.apply(account.item_metrics, :price, described_class.parse("10"))

      expect(result.count).to eq(1)
    end

    it "nunca deixa nulo passar" do
      create(:item_metric, ml_account: account, coverage_days: nil)
      create(:item_metric, ml_account: account, coverage_days: 5)

      result = described_class.apply(account.item_metrics, :coverage_days, described_class.parse(">0"))

      expect(result.count).to eq(1)
    end
  end
end
