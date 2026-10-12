require "rails_helper"

RSpec.describe Olist::ChangeProduct do
  let(:company) { create(:company) }
  let(:user) { create(:user, :admin, company: company) }
  let(:connection) { create(:olist_connection, company: company) }
  let(:product) { create(:olist_product, company: company, olist_id: 555, price: 100, promo_price: 0, stock_balance: 10) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }
  let(:changer) { described_class.new(connection: connection, user: user, product: product) }

  describe "#change_price" do
    it "chama o Olist, registra a alteração (antes e pedido) e atualiza a cópia local" do
      stub = stub_request(:put, "#{base}/produtos/555/preco")
        .with(body: { preco: 129.9, precoPromocional: 99.9 }.to_json, headers: { "Authorization" => "Bearer olist-access-token" })
        .to_return(status: 204, body: "")

      change = changer.change_price(price: "129,90", promo_price: 99.9)

      expect(stub).to have_been_requested.once
      expect(change).to have_attributes(kind: "price", status: "done", olist_product_id: 555, user_id: user.id)
      expect(change.before).to eq("price" => 100.0, "promo_price" => 0.0)
      expect(change.request).to eq("price" => 129.9, "promo_price" => 99.9)
      expect(product.reload).to have_attributes(price: 129.9, promo_price: 99.9)
    end

    it "preço inválido ou negativo: nada é chamado nem registrado" do
      expect { changer.change_price(price: "abc") }.to raise_error(described_class::Invalid)
      expect { changer.change_price(price: -1) }.to raise_error(described_class::Invalid)

      expect(WebMock).not_to have_requested(:put, /api.tiny.com.br/)
      expect(OlistChange.count).to eq(0)
    end

    it "falha do Olist: registra failed, não repete e não altera a cópia local" do
      stub_request(:put, "#{base}/produtos/555/preco").to_return(status: 500, body: "erro")

      expect { changer.change_price(price: 120) }.to raise_error(Olist::Client::Error)

      expect(WebMock).to have_requested(:put, "#{base}/produtos/555/preco").once
      expect(OlistChange.last).to have_attributes(status: "failed", kind: "price")
      expect(OlistChange.last.error).to include("500")
      expect(product.reload.price).to eq(100)
    end
  end

  describe "#change_stock" do
    let(:stock_after) { { "id" => 555, "saldo" => 15.0, "reservado" => 2.0, "disponivel" => 13.0, "depositos" => [] } }

    it "lança uma entrada, registra e relê o saldo no Olist" do
      stub = stub_request(:post, "#{base}/estoque/555")
        .with(body: { tipo: "E", quantidade: 5.0, precoUnitario: 38.5, observacoes: "reposição" }.to_json)
        .to_return(status: 200, body: { idLancamento: 77 }.to_json)
      stub_request(:get, "#{base}/estoque/555").to_return(status: 200, body: stock_after.to_json)

      change = changer.change_stock(type: "e", quantity: 5, note: "reposição")

      expect(stub).to have_been_requested.once
      expect(change).to have_attributes(kind: "stock", status: "done")
      expect(change.response).to eq("idLancamento" => 77)
      expect(change.before).to eq("balance" => 10.0, "reserved" => 2.0)
      expect(product.reload).to have_attributes(stock_balance: 15, stock_available: 13)
    end

    it "balanço aceita zero; entrada e saída exigem quantidade maior que zero" do
      stub_request(:post, "#{base}/estoque/555").to_return(status: 200, body: "{}")
      stub_request(:get, "#{base}/estoque/555").to_return(status: 200, body: stock_after.to_json)

      expect(changer.change_stock(type: "B", quantity: 0).status).to eq("done")
      expect { changer.change_stock(type: "E", quantity: 0) }.to raise_error(described_class::Invalid)
      expect { changer.change_stock(type: "S", quantity: -3) }.to raise_error(described_class::Invalid)
    end

    it "tipo inválido" do
      expect { changer.change_stock(type: "X", quantity: 1) }.to raise_error(described_class::Invalid, /Tipo/)
      expect(OlistChange.count).to eq(0)
    end

    it "timeout no lançamento: registra failed e NÃO repete (evita duplicar a movimentação)" do
      stub_request(:post, "#{base}/estoque/555").to_timeout

      expect { changer.change_stock(type: "E", quantity: 1) }.to raise_error(Olist::Client::Error)

      expect(WebMock).to have_requested(:post, "#{base}/estoque/555").once
      expect(OlistChange.last.status).to eq("failed")
    end
  end
end
