require "rails_helper"

RSpec.describe Fx::UsdBrl do
  before { described_class.reset! }
  after { described_class.reset! }

  let(:url) { "https://economia.awesomeapi.com.br/json/last/USD-BRL" }

  it "lê a cotação de venda e guarda por algumas horas" do
    req = stub_request(:get, url).to_return(status: 200, body: { USDBRL: { bid: "5.8210", ask: "5.8215" } }.to_json)

    expect(described_class.rate).to eq(5.8215)
    expect(described_class.rate).to eq(5.8215)
    expect(req).to have_been_requested.once
  end

  it "fonte fora do ar: usa a última que deu certo e, sem nenhuma, nil" do
    stub_request(:get, url).to_return(status: 500).then.to_return(status: 200, body: { USDBRL: { ask: "5.9" } }.to_json).then.to_return(status: 500)

    expect(described_class.rate).to be_nil
    expect(described_class.rate).to eq(5.9)
    travel 7.hours do
      expect(described_class.rate).to eq(5.9)
    end
  end
end
