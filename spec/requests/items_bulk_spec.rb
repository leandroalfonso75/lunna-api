require "rails_helper"

# Anúncios (pedido do usuário em 24/11/2026): curva ABC e data de criação na tabela, ordenação por elas, edição em lote
# (um anúncio ou vários com os mesmos SKUs) e exclusão no Mercado Livre. O ML é sempre simulado (WebMock).
RSpec.describe "/api/items: curva, data de criação, editar e excluir em lote", type: :request do
  let(:company) { create(:company, abc_cut_a: 80, abc_cut_b: 95) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }

  def listing(id, revenue:, created:, sku: nil, refs: [], status: "active")
    create(:item_metric, ml_account: account, item_id: id, title: "Anúncio #{id}", status: status, sku: sku, revenue_30d: revenue, units_30d: revenue.positive? ? 1 : 0)
    create(:ml_item, ml_account: account, item_id: id, title: "Anúncio #{id}", status: status, sku: sku, inventory_refs: refs, date_created: created)
  end

  describe "curva ABC e data de criação" do
    before do
      listing("MLBA", revenue: 800, created: Time.zone.parse("2024-03-10"))
      listing("MLBB", revenue: 150, created: Time.zone.parse("2026-01-05"))
      listing("MLBC", revenue: 50, created: Time.zone.parse("2025-07-20"))
      listing("MLBZ", revenue: 0, created: Time.zone.parse("2026-11-01"))
    end

    def ids(params = {})
      get "/api/items", params: { account_id: account.id }.merge(params), headers: auth_headers(member)
      json["items"].map { |i| i["id"] }
    end

    it "cada anúncio traz a curva (a mesma da Curva ABC) e a data de criação no ML" do
      ids
      by_id = json["items"].index_by { |i| i["id"] }
      expect(by_id.transform_values { |i| i["curve"] }).to eq("MLBA" => "A", "MLBB" => "B", "MLBC" => "C", "MLBZ" => "C")
      expect(Time.zone.parse(by_id["MLBA"]["date_created"]).to_date).to eq(Date.new(2024, 3, 10))
    end

    it "ordena pela curva e pela data de criação, sobre a lista inteira" do
      expect(ids(sort: "curve")).to eq(%w[MLBA MLBB MLBC MLBZ]) # A, B, C; empate pela ordem padrão
      expect(json).to include("sort" => "curve", "dir" => "asc")
      expect(ids(sort: "curve", dir: "desc").first(2)).to match_array(%w[MLBC MLBZ])
      expect(ids(sort: "date_created")).to eq(%w[MLBZ MLBB MLBC MLBA]) # mais novo primeiro
      expect(json["dir"]).to eq("desc")
      expect(ids(sort: "date_created", dir: "asc")).to eq(%w[MLBA MLBC MLBB MLBZ])
      expect(ids(sort: "curve", per_page: 2, page: 2)).to eq(%w[MLBC MLBZ])
    end

    it "filtra os criados há mais de N dias, também nas contagens das abas; vazio ou inválido não filtra" do
      travel_to(Time.zone.parse("2026-11-24 12:00")) do
        expect(ids(created_older_than: 90, sort: "date_created")).to eq(%w[MLBB MLBC MLBA]) # MLBZ é de 01/11
        expect(json["status_counts"]["active"]).to eq(3)
        expect(json["created_older_than"]).to eq(90)
        expect(ids(created_older_than: 365, sort: "date_created")).to eq(%w[MLBC MLBA])
        expect(ids(created_older_than: 1000, sort: "date_created")).to eq([])
        expect(ids(created_older_than: "abc").size).to eq(4)
        expect(json["created_older_than"]).to be_nil
        expect(ids(created_older_than: "").size).to eq(4)
      end
    end

    it "Quantidade de Vendas: sem vendas ou N vendas ou mais (total do ML), cumulativo com a data de criação" do
      { "MLBA" => 1200, "MLBB" => 30, "MLBC" => 0, "MLBZ" => 5 }.each { |id, sold| account.ml_items.find_by(item_id: id).update!(sold_quantity: sold) }
      travel_to(Time.zone.parse("2026-11-24 12:00")) do
        expect(ids(sales: "none")).to eq([ "MLBC" ])
        expect(json["status_counts"]["active"]).to eq(1)
        expect(json["sales"]).to eq("none")
        expect(ids(sales: 5, sort: "date_created")).to eq(%w[MLBZ MLBB MLBA])
        expect(ids(sales: 25, sort: "date_created")).to eq(%w[MLBB MLBA])
        expect(ids(sales: 1000)).to eq([ "MLBA" ])
        expect(json["sales"]).to eq(1000)
        expect(ids(sales: 5000)).to eq([])
        # cumulativo: criados há mais de 90 dias E com 25 vendas ou mais
        expect(ids(sales: 25, created_older_than: 365, sort: "date_created")).to eq([ "MLBA" ])
        expect(ids(sales: "none", created_older_than: 90)).to eq([ "MLBC" ])
        expect(ids(sales: "xyz").size).to eq(4)
        expect(json["sales"]).to be_nil
      end
    end

    it "aba Catálogo também filtra pela data de criação" do
      account.ml_items.where(item_id: %w[MLBA MLBZ]).update_all(catalog_listing: true)
      travel_to(Time.zone.parse("2026-11-24 12:00")) do
        get "/api/items/catalog", params: { account_id: account.id, created_older_than: 30 }, headers: auth_headers(member)
        expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLBA" ])
        expect(json["counts"]["total"]).to eq(1)

        account.ml_items.find_by(item_id: "MLBA").update!(sold_quantity: 0)
        get "/api/items/catalog", params: { account_id: account.id, created_older_than: 30, sales: 10 }, headers: auth_headers(member)
        expect(json["items"]).to eq([])
      end
    end
  end

  describe "editar selecionados" do
    it "um anúncio sozinho pode sempre" do
      listing("MLB1", revenue: 0, created: 1.year.ago)
      get "/api/items/bulk_edit", params: { account_id: account.id, item_ids: [ "MLB1" ] }, headers: auth_headers(member)
      expect(response).to have_http_status(:ok)
      expect(json).to include("ok" => true, "others" => [])
      expect(json["primary"]).to include("item_id" => "MLB1")
    end

    it "vários só com o(s) mesmo(s) SKU(s), inclusive pelas variações" do
      listing("MLB1", revenue: 0, created: 1.year.ago, sku: "SEC-1")
      listing("MLB2", revenue: 0, created: 1.year.ago, sku: "SEC-1")
      listing("MLB3", revenue: 0, created: 1.year.ago, refs: [ { "sku" => "SEC-110" }, { "sku" => "SEC-220" } ])
      listing("MLB4", revenue: 0, created: 1.year.ago, refs: [ { "sku" => "SEC-220" }, { "sku" => "SEC-110" } ])
      listing("MLB5", revenue: 0, created: 1.year.ago, sku: "OUTRO")

      get "/api/items/bulk_edit", params: { account_id: account.id, item_ids: %w[MLB1 MLB2] }, headers: auth_headers(member)
      expect(json).to include("ok" => true, "skus" => [ "SEC-1" ])
      expect(json["others"].map { |o| o["item_id"] }).to eq([ "MLB2" ])

      get "/api/items/bulk_edit", params: { account_id: account.id, item_ids: %w[MLB3 MLB4] }, headers: auth_headers(member)
      expect(json).to include("ok" => true, "skus" => %w[SEC-110 SEC-220])

      get "/api/items/bulk_edit", params: { account_id: account.id, item_ids: %w[MLB1 MLB5] }, headers: auth_headers(member)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["ok"]).to be(false)
      expect(json["message"]).to include("mesmo(s) SKU(s)", "MLB5 tem OUTRO")
    end
  end

  describe "excluir selecionados" do
    before do
      listing("MLB1", revenue: 0, created: 1.year.ago)
      listing("MLB2", revenue: 0, created: 1.year.ago, status: "paused")
      allow(Ml::OAuth).to receive(:refresh!)
    end

    it "exige administrador e confirmação" do
      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: [ "MLB1" ], confirm: true }, headers: auth_headers(member)
      expect(response).to have_http_status(:forbidden)

      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: [ "MLB1" ] }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(a_request(:put, %r{#{ml}/items/})).not_to have_been_made
    end

    it "finaliza e marca como excluído no ML, um por um; o recusado não impede os outros" do
      close1 = stub_request(:put, "#{ml}/items/MLB1").with(body: { status: "closed" }.to_json).to_return(status: 200, body: "{}")
      del1 = stub_request(:put, "#{ml}/items/MLB1").with(body: { deleted: "true" }.to_json).to_return(status: 200, body: "{}")
      stub_request(:put, "#{ml}/items/MLB2").with(body: { status: "closed" }.to_json)
        .to_return(status: 400, body: { message: "Validation error", cause: [ { message: "Item with stock in fulfillment cannot be closed" } ] }.to_json)
      stub_request(:get, %r{#{ml}/items/MLB2\?}).to_return(status: 200, body: { id: "MLB2", status: "paused" }.to_json)

      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: %w[MLB1 MLB2 MLBX], confirm: true }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(close1).to have_been_requested.once
      expect(del1).to have_been_requested.once
      expect(json["ok"]).to be(false)
      expect(json["message"]).to eq("1 de 3 anúncio(s) excluído(s). Veja os que o Mercado Livre recusou.")
      results = json["results"].index_by { |r| r["item_id"] }
      expect(results["MLB1"]).to include("ok" => true)
      expect(results["MLB2"]).to include("ok" => false)
      expect(results["MLB2"]["message"]).to include("cannot be closed")
      expect(results["MLBX"]["message"]).to include("não encontrado")

      expect(account.ml_items.find_by(item_id: "MLB1").status).to eq("closed")
      expect(account.item_metrics.find_by(item_id: "MLB1").status).to eq("closed")
      expect(account.ml_items.find_by(item_id: "MLB2").status).to eq("paused")
      expect(account.ml_item_edits.where(kind: "exclusao").pluck(:item_id, :ok)).to match_array([ [ "MLB1", true ], [ "MLB2", false ] ])
    end
  end
end
