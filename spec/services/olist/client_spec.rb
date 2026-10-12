require "rails_helper"

RSpec.describe Olist::Client do
  let(:connection) { create(:olist_connection) }
  let(:sleeps) { [] }
  let(:client) { described_class.new(connection, sleeper: ->(seconds) { sleeps << seconds }) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }

  it "lista produtos com o Bearer token e a paginação" do
    stub_request(:get, "#{base}/produtos")
      .with(query: { limit: "20", offset: "0", situacao: "A" }, headers: { "Authorization" => "Bearer olist-access-token" })
      .to_return(status: 200, body: { itens: [ { id: 1, sku: "SKU1", descricao: "Produto", situacao: "A" } ], paginacao: { total: 1 } }.to_json)

    result = client.products(limit: 20, offset: 0, situacao: "A")

    expect(result["itens"].first).to include("id" => 1, "sku" => "SKU1")
  end

  it "busca um produto e o histórico de custos" do
    stub_request(:get, "#{base}/produtos/10").to_return(status: 200, body: { id: 10 }.to_json)
    stub_request(:get, "#{base}/produtos/10/custos").to_return(status: 200, body: { itens: [] }.to_json)

    expect(client.product(10)).to eq("id" => 10)
    expect(client.product_costs(10)).to eq("itens" => [])
  end

  it "rejeita id de produto que não é número (nada de path livre)" do
    expect { client.product("10/../x") }.to raise_error(ArgumentError)
  end

  it "404 vira NotFound" do
    stub_request(:get, "#{base}/produtos/99").to_return(status: 404, body: "{}")

    expect { client.product(99) }.to raise_error(described_class::NotFound)
  end

  it "repete em 429/5xx e depois consegue" do
    stub_request(:get, "#{base}/produtos/5").to_return({ status: 429, body: "" }, { status: 200, body: { id: 5 }.to_json })

    expect(client.product(5)).to eq("id" => 5)
    expect(sleeps).to eq([ 0.9 ])
  end

  it "desiste depois de 3 tentativas" do
    stub_request(:get, "#{base}/produtos/6").to_return(status: 500, body: "erro")

    expect { client.product(6) }.to raise_error(described_class::Error, /500/)
    expect(sleeps.size).to eq(2)
  end

  it "renova o token antes de chamar quando está perto de expirar" do
    connection.update!(expires_at: 1.minute.from_now)
    stub_env("OLIST_CLIENT_ID" => "c", "OLIST_CLIENT_SECRET" => "s", "API_URL" => "https://api.lunna.test")
    stub_request(:post, "https://accounts.tiny.com.br/realms/tiny/protocol/openid-connect/token")
      .to_return(status: 200, body: { access_token: "novo", refresh_token: "r2", expires_in: 14_400 }.to_json)
    stub_request(:get, "#{base}/produtos/7").with(headers: { "Authorization" => "Bearer novo" }).to_return(status: 200, body: "{}")

    client.product(7)

    expect(WebMock).to have_requested(:get, "#{base}/produtos/7").with(headers: { "Authorization" => "Bearer novo" })
  end

  it "recusa chamar quando a conexão precisa ser refeita" do
    connection.update!(status: "reauth_required")

    expect { client.product(1) }.to raise_error(described_class::Error, /refeita/)
    expect(WebMock).not_to have_requested(:get, /api.tiny.com.br/)
  end
end
