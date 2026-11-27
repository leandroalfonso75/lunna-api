require "rails_helper"

# Urgência e prazo do Full em português, nunca o código cru do Mercado Livre (IN_TWO_WEEKS apareceu cru em 27/11/2026).
RSpec.describe MlFullReplenishment do
  it "traduz todos os valores conhecidos e dá um texto legível aos desconhecidos" do
    expect(described_class.urgency_label("IN_TWO_WEEKS")).to eq("Em duas semanas")
    expect(described_class.urgency_label("URGENT")).to eq("Urgente")
    expect(described_class.urgency_label("NEW_CODE_FROM_ML")).to eq("Prazo não classificado")
    expect(described_class.urgency_label(nil)).to be_nil
    expect(described_class.deadline_label("IN_TWO_WEEKS")).to eq("em duas semanas")
    expect(described_class.deadline_label("SOMETHING_ELSE")).to eq("prazo não classificado")
    expect(described_class::URGENCY_ORDER).to eq(%w[URGENT THIS_WEEK NEXT_WEEK IN_TWO_WEEKS NO_URGENCY])
  end
end
