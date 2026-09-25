require "rails_helper"

RSpec.describe Abc::Classifier do
  let(:params) { abc_params }

  describe "curva pelo acumulado antes do anúncio (cut_a=80, cut_b=95)" do
    it "acumulado antes exatamente 80 -> B" do
      rows = [
        build_metric(item_id: "MLB1", revenue_30d: 80, prev_revenue_30d: 0),
        build_metric(item_id: "MLB2", revenue_30d: 15, prev_revenue_30d: 0),
        build_metric(item_id: "MLB3", revenue_30d: 5, prev_revenue_30d: 0)
      ]

      result = described_class.call(rows, params)

      expect(result.rows.find { |r| r.metric.item_id == "MLB2" }.curve).to eq("B")
    end

    it "acumulado antes 79,99 -> A" do
      rows = [
        build_metric(item_id: "MLB1", revenue_30d: 7999, prev_revenue_30d: 0),
        build_metric(item_id: "MLB2", revenue_30d: 2001, prev_revenue_30d: 0)
      ]

      result = described_class.call(rows, params)

      expect(result.rows.find { |r| r.metric.item_id == "MLB2" }.curve).to eq("A")
    end

    it "acumulado antes exatamente 95 -> C" do
      rows = [
        build_metric(item_id: "MLB1", revenue_30d: 95, prev_revenue_30d: 0),
        build_metric(item_id: "MLB2", revenue_30d: 5, prev_revenue_30d: 0)
      ]

      result = described_class.call(rows, params)

      expect(result.rows.find { |r| r.metric.item_id == "MLB2" }.curve).to eq("C")
    end

    it "sem faturamento -> sempre C, mesmo com acumulado antes baixo" do
      rows = [
        build_metric(item_id: "MLB1", status: "paused", revenue_30d: 0, prev_revenue_30d: 0, units_30d: 0, prev_units_30d: 0),
        build_metric(item_id: "MLB2", revenue_30d: 100, prev_revenue_30d: 0)
      ]

      result = described_class.call(rows, params)

      expect(result.rows.find { |r| r.metric.item_id == "MLB1" }.curve).to eq("C")
    end
  end

  describe "grupo e units_change_state da curva A (up_pct=10, down_pct=-15)" do
    it "variação exatamente +10 -> up / ok" do
      row = build_metric(revenue_30d: 100, prev_revenue_30d: 0, units_30d: 110, prev_units_30d: 100)

      classified = described_class.call([ row ], params).rows.first

      expect(classified.curve).to eq("A")
      expect(classified.group).to eq("up")
      expect(classified.units_change_pct).to eq(10.0)
      expect(classified.units_change_state).to eq("ok")
    end

    it "variação exatamente -15 -> flat / nil" do
      row = build_metric(revenue_30d: 100, prev_revenue_30d: 0, units_30d: 85, prev_units_30d: 100)

      classified = described_class.call([ row ], params).rows.first

      expect(classified.group).to eq("flat")
      expect(classified.units_change_pct).to eq(-15.0)
      expect(classified.units_change_state).to be_nil
    end

    it "variação -15,01 -> down / bad" do
      row = build_metric(revenue_30d: 100, prev_revenue_30d: 0, units_30d: 8499, prev_units_30d: 10000)

      classified = described_class.call([ row ], params).rows.first

      expect(classified.group).to eq("down")
      expect(classified.units_change_pct).to be_within(0.001).of(-15.01)
      expect(classified.units_change_state).to eq("bad")
    end

    it "novo (sem venda anterior, com venda agora) conta como Vendendo" do
      row = build_metric(revenue_30d: 100, prev_revenue_30d: 0, units_30d: 5, prev_units_30d: 0)

      classified = described_class.call([ row ], params).rows.first

      expect(classified.is_new).to be true
      expect(classified.group).to eq("up")
      expect(classified.units_change_pct).to be_nil
      expect(classified.units_change_state).to eq("ok")
    end

    it "sem venda nenhuma -> Estagnado, sem state" do
      row = build_metric(revenue_30d: 100, prev_revenue_30d: 0, units_30d: 0, prev_units_30d: 0)

      classified = described_class.call([ row ], params).rows.first

      expect(classified.is_new).to be false
      expect(classified.group).to eq("flat")
      expect(classified.units_change_state).to be_nil
    end
  end

  describe "mediana da conversão 30d (>= 100 visitas)" do
    it "número ímpar de anúncios elegíveis" do
      rows = [
        build_metric(item_id: "A", revenue_30d: 10, visits_30d: 100, conversion_30d: 1.0),
        build_metric(item_id: "B", revenue_30d: 10, visits_30d: 150, conversion_30d: 5.0),
        build_metric(item_id: "C", revenue_30d: 10, visits_30d: 200, conversion_30d: 3.0),
        build_metric(item_id: "D", revenue_30d: 10, visits_30d: 99, conversion_30d: 100.0)
      ]

      expect(described_class.call(rows, params).conversion_median).to eq(3.0)
    end

    it "número par de anúncios elegíveis (média dos dois do meio)" do
      rows = [
        build_metric(item_id: "A", revenue_30d: 10, visits_30d: 100, conversion_30d: 1.0),
        build_metric(item_id: "B", revenue_30d: 10, visits_30d: 100, conversion_30d: 3.0),
        build_metric(item_id: "C", revenue_30d: 10, visits_30d: 100, conversion_30d: 5.0),
        build_metric(item_id: "D", revenue_30d: 10, visits_30d: 100, conversion_30d: 7.0)
      ]

      expect(described_class.call(rows, params).conversion_median).to eq(4.0)
    end

    it "nenhum anúncio elegível -> nil" do
      rows = [ build_metric(revenue_30d: 10, visits_30d: 50, conversion_30d: 10.0) ]

      expect(described_class.call(rows, params).conversion_median).to be_nil
    end
  end

  describe "universo" do
    it "exclui closed/inactive sem faturamento nos últimos 60 dias" do
      rows = [
        build_metric(item_id: "CLOSED", status: "closed", revenue_30d: 0, prev_revenue_30d: 0),
        build_metric(item_id: "INACTIVE", status: "inactive", revenue_30d: 0, prev_revenue_30d: 0),
        build_metric(item_id: "CLOSED_COM_VENDA", status: "closed", revenue_30d: 0, prev_revenue_30d: 10),
        build_metric(item_id: "PAUSED", status: "paused", revenue_30d: 0, prev_revenue_30d: 0),
        build_metric(item_id: "ACTIVE", status: "active", revenue_30d: 0, prev_revenue_30d: 0)
      ]

      ids = described_class.call(rows, params).rows.map { |r| r.metric.item_id }

      expect(ids).to contain_exactly("CLOSED_COM_VENDA", "PAUSED", "ACTIVE")
    end
  end

  describe "resumo por curva e grupos" do
    it "soma quantidade, faturamento e participação por curva" do
      rows = [
        build_metric(item_id: "A1", revenue_30d: 80, prev_revenue_30d: 0),
        build_metric(item_id: "B1", revenue_30d: 15, prev_revenue_30d: 0),
        build_metric(item_id: "C1", revenue_30d: 5, prev_revenue_30d: 0)
      ]

      summary = described_class.call(rows, params).summary

      expect(summary).to contain_exactly(
        { curve: "A", count: 1, revenue: 80.0, share_pct: 80.0 },
        { curve: "B", count: 1, revenue: 15.0, share_pct: 15.0 },
        { curve: "C", count: 1, revenue: 5.0, share_pct: 5.0 }
      )
    end

    it "groups sempre traz up/flat/down, mesmo zerados" do
      groups = described_class.call([], params).groups

      expect(groups.keys).to contain_exactly(:up, :flat, :down)
      expect(groups[:up][:label]).to eq("Vendendo")
      expect(groups[:up][:count]).to eq(0)
    end
  end
end
