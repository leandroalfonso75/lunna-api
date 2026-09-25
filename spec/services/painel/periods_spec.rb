require "rails_helper"

RSpec.describe Painel::Periods do
  let(:today) { Date.new(2026, 9, 24) }

  it "monta as janelas de dias fechados da SPEC 6" do
    periods = described_class.call(today)

    expect(periods[:today]).to eq(today..today)
    expect(periods[:week]).to eq((today - 7)..(today - 1))
    expect(periods[:prev_week]).to eq((today - 14)..(today - 8))
    expect(periods[:month]).to eq((today - 30)..(today - 1))
    expect(periods[:prev_month]).to eq((today - 60)..(today - 31))
    expect(periods[:daily]).to eq((today - 14)..today)
  end

  it "cada período continua um Range de verdade (dá pra usar em where)" do
    periods = described_class.call(today)

    expect(periods[:week]).to be_a(Range)
    expect(periods[:week].cover?(today - 5)).to be true
  end

  it "as_json sai como {from, to} ISO, não o to_s padrão do Range" do
    periods = described_class.call(today)

    expect(periods[:week].as_json).to eq(from: (today - 7).iso8601, to: (today - 1).iso8601)
  end

  it "usa Date.current quando não recebe today" do
    travel_to Time.zone.local(2026, 9, 24, 12, 0) do
      expect(described_class.call[:today]).to eq(Date.current..Date.current)
    end
  end
end
