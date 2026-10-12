require "rails_helper"

RSpec.describe "Produtos do Olist", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }

  describe "GET /api/olist/products" do
    it "lista só os produtos da própria empresa, com busca e paginação" do
      create(:olist_product, company: company, description: "Secador Mondial", sku: "SEC-1", status: "A")
      create(:olist_product, company: company, description: "Difusor de cachos", sku: "DIF-1", status: "I")
      create(:olist_product, description: "Secador de outra empresa")

      get "/api/olist/products", params: { q: "secador" }, headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      expect(json["products"].map { |p| p["sku"] }).to eq([ "SEC-1" ])
      expect(json["total"]).to eq(1)
    end

    it "filtra por situação e limita a página a 100" do
      create(:olist_product, company: company, status: "A")
      create(:olist_product, company: company, status: "I")

      get "/api/olist/products", params: { status: "I", limit: 5000 }, headers: auth_headers(member)

      expect(json["products"].size).to eq(1)
      expect(json["limit"]).to eq(100)
    end

    it "traz preço, custo e estoque" do
      create(:olist_product, company: company, price: 229.9, cost_price: 80, stock_balance: 4, stock_reserved: 1, stock_available: 3)

      get "/api/olist/products", headers: auth_headers(member)

      expect(json["products"].first).to include("price" => "229.9", "cost_price" => "80.0")
      expect(json["products"].first["stock"]).to include("balance" => "4.0", "available" => "3.0")
    end
  end

  describe "estoque Olist + Full + total" do
    let(:account) { create(:ml_account, company: company) }

    def link_full(product, available:, not_available: 0)
      create(:ml_item, ml_account: account, sku: product.sku, logistic_type: "fulfillment", status: "active",
        inventory_refs: [ { "sku" => product.sku, "inventory_id" => "INV-#{product.olist_id}" } ])
      MlFullStock.create!(ml_account: account, inventory_id: "INV-#{product.olist_id}", available_units: available,
        not_available_units: not_available, total_units: available + not_available, synced_at: Time.current)
    end

    it "mostra o disponível do Olist, o do Full (ML) e o total somado" do
      product = create(:olist_product, company: company, stock_available: 8)
      link_full(product, available: 12, not_available: 3)

      get "/api/olist/products", headers: auth_headers(member)

      stock = json["products"].first["stock"]
      expect(stock["available"]).to eq("8.0")
      expect(stock["full"]).to include("linked" => true, "available" => 12, "not_available" => 3, "listings" => 1)
      expect(stock["total_available"].to_f).to eq(20.0)
    end

    it "sem anúncio Full, o total é só o do Olist" do
      create(:olist_product, company: company, stock_available: 8)

      get "/api/olist/products", headers: auth_headers(member)

      stock = json["products"].first["stock"]
      expect(stock["full"]).to include("linked" => false, "available" => nil)
      expect(stock["total_available"]).to eq("8.0")
    end

    it "disponível negativo no Olist reduz o total (reservado maior que o saldo)" do
      product = create(:olist_product, company: company, stock_available: -3)
      link_full(product, available: 10)

      get "/api/olist/products/#{product.olist_id}", headers: auth_headers(member)

      expect(json["product"]["stock"]["total_available"].to_f).to eq(7.0)
    end

    it "produto excluído no Olist não recebe o Full (SKU reaproveitado por outro cadastro)" do
      active = create(:olist_product, company: company, sku: "DUP", status: "A", stock_available: 5)
      excluded = create(:olist_product, company: company, sku: "DUP", status: "E", stock_available: 0)
      link_full(active, available: 10)

      get "/api/olist/products", params: { q: "DUP" }, headers: auth_headers(member)

      by_id = json["products"].index_by { |p| p["id"] }
      expect(by_id[active.olist_id]["stock"]["total_available"].to_f).to eq(15.0)
      expect(by_id[excluded.olist_id]["stock"]["full"]["linked"]).to be false
      expect(by_id[excluded.olist_id]["stock"]["total_available"].to_f).to eq(0.0)
    end

    it "não usa o estoque Full de outra empresa" do
      product = create(:olist_product, company: company, stock_available: 1)
      other_account = create(:ml_account)
      create(:ml_item, ml_account: other_account, sku: product.sku, logistic_type: "fulfillment", status: "active",
        inventory_refs: [ { "sku" => product.sku, "inventory_id" => "INV-O" } ])
      MlFullStock.create!(ml_account: other_account, inventory_id: "INV-O", available_units: 99, total_units: 99, synced_at: Time.current)

      get "/api/olist/products/#{product.olist_id}", headers: auth_headers(member)

      expect(json["product"]["stock"]["full"]["linked"]).to be false
    end
  end

  describe "GET /api/olist/products/:id" do
    it "produto de outra empresa é 404" do
      other = create(:olist_product)

      get "/api/olist/products/#{other.olist_id}", headers: auth_headers(member)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/olist/products/:id/price" do
    let!(:product) { create(:olist_product, company: company, olist_id: 555, price: 100) }

    before { create(:olist_connection, company: company) }

    it "sem confirm=true nada acontece" do
      patch "/api/olist/products/555/price", params: { price: 150 }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("Confirmação obrigatória")
      expect(WebMock).not_to have_requested(:put, /api.tiny.com.br/)
      expect(OlistChange.count).to eq(0)
    end

    it "admin confirma: altera no Olist, registra e devolve o produto" do
      stub_request(:put, "#{base}/produtos/555/preco").with(body: { preco: 150.0 }.to_json).to_return(status: 204, body: "")

      patch "/api/olist/products/555/price", params: { price: 150, confirm: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(json["change"]).to include("kind" => "price", "status" => "done", "changed_by" => admin.name)
      expect(json["product"]["price"]).to eq("150.0")
    end

    it "member não pode (403)" do
      patch "/api/olist/products/555/price", params: { price: 150, confirm: true }, headers: auth_headers(member), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "preço inválido é 422" do
      patch "/api/olist/products/555/price", params: { price: "abc", confirm: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "Olist recusa: 502, registro failed e preço local intacto" do
      stub_request(:put, "#{base}/produtos/555/preco").to_return(status: 400, body: "{}")

      patch "/api/olist/products/555/price", params: { price: 150, confirm: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(OlistChange.last.status).to eq("failed")
      expect(product.reload.price).to eq(100)
    end

    it "sem conexão com o Olist é 422" do
      OlistConnection.destroy_all

      patch "/api/olist/products/555/price", params: { price: 150, confirm: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "produto de outra empresa é 404" do
      other = create(:olist_product)

      patch "/api/olist/products/#{other.olist_id}/price", params: { price: 1, confirm: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/olist/products/:id/stock" do
    let!(:product) { create(:olist_product, company: company, olist_id: 555, stock_balance: 10) }

    before { create(:olist_connection, company: company) }

    it "sem confirm=true nada acontece" do
      post "/api/olist/products/555/stock", params: { type: "E", quantity: 3 }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(WebMock).not_to have_requested(:post, /api.tiny.com.br/)
    end

    it "admin confirma: lança no Olist e devolve o saldo atualizado" do
      stub_request(:post, "#{base}/estoque/555").to_return(status: 200, body: { idLancamento: 1 }.to_json)
      stub_request(:get, "#{base}/estoque/555").to_return(status: 200,
        body: { saldo: 13.0, reservado: 2.0, disponivel: 11.0, depositos: [] }.to_json)

      post "/api/olist/products/555/stock", params: { type: "E", quantity: 3, confirm: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(json["product"]["stock"]).to include("balance" => "13.0")
      expect(json["change"]).to include("kind" => "stock", "status" => "done")
    end

    it "member não pode (403)" do
      post "/api/olist/products/555/stock", params: { type: "E", quantity: 3, confirm: true }, headers: auth_headers(member), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/olist/changes" do
    it "admin vê o registro da própria empresa, do mais novo para o mais antigo" do
      older = create(:olist_change, company: company, created_at: 2.days.ago)
      newer = create(:olist_change, company: company, created_at: 1.day.ago)
      other = create(:olist_change)

      get "/api/olist/changes", headers: auth_headers(admin)

      ids = json["changes"].map { |c| c["id"] }
      expect(ids).to eq([ newer.id, older.id ])
      expect(ids).not_to include(other.id)
    end

    it "member não pode (403)" do
      get "/api/olist/changes", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
