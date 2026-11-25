require "rails_helper"

# Anúncios › aba Tradicional (pedido do usuário em 25/11/2026): só os anúncios que não são de catálogo, com a informação
# de sincronização com catálogo (mesma regra de Promoções) e o código/link do anúncio de catálogo. Excluir um tradicional
# sincronizado exclui também o catálogo, só com a confirmação (with_catalog). O ML é sempre simulado (WebMock).
RSpec.describe "/api/items: aba Tradicional e exclusão com catálogo", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }

  def listing(id, catalog: false, relations: [], sold: 0, created: 1.year.ago, status: "active")
    create(:item_metric, ml_account: account, item_id: id, title: "Anúncio #{id}", status: status, catalog: catalog)
    create(:ml_item, ml_account: account, item_id: id, title: "Anúncio #{id}", status: status, catalog_listing: catalog,
                     item_relations: relations.map { |r| { "id" => r } }, sold_quantity: sold, date_created: created,
                     permalink: "https://produto.mercadolivre.com.br/#{id}")
  end

  before do
    listing("MLBT1", sold: 30)                                       # sincronizado (relação no catálogo)
    listing("MLBC1", catalog: true, relations: [ "MLBT1" ], sold: 30)
    listing("MLBT2", relations: [ "MLBC2" ], created: 10.days.ago)   # sincronizado (relação no tradicional)
    listing("MLBC2", catalog: true)
    listing("MLBT3", status: "paused")                               # não sincronizado
    listing("MLBC3", catalog: true)                                  # catálogo sem sincronização
  end

  def items(params = {})
    get "/api/items", params: { account_id: account.id }.merge(params), headers: auth_headers(member)
    json["items"].index_by { |i| i["id"] }
  end

  it "kind=traditional traz só os tradicionais, com as contagens das abas acompanhando" do
    expect(items(status: "all").keys).to match_array(%w[MLBT1 MLBC1 MLBT2 MLBC2 MLBT3 MLBC3])
    rows = items(kind: "traditional", status: "all")
    expect(rows.keys).to match_array(%w[MLBT1 MLBT2 MLBT3])
    expect(json["status_counts"]).to include("active" => 2, "paused" => 1)
  end

  it "cada tradicional traz o(s) catálogo(s) sincronizado(s) com o link; não sincronizado vem vazio; catálogo vem nil" do
    rows = items(status: "all")
    expect(rows["MLBT1"]["catalog_sync"]).to eq([ { "item_id" => "MLBC1", "permalink" => "https://produto.mercadolivre.com.br/MLBC1", "status" => "active" } ])
    expect(rows["MLBT2"]["catalog_sync"].map { |c| c["item_id"] }).to eq([ "MLBC2" ])
    expect(rows["MLBT3"]["catalog_sync"]).to eq([])
    expect(rows["MLBC1"]["catalog_sync"]).to be_nil
  end

  it "respeita os filtros de criação e de vendas" do
    expect(items(kind: "traditional", status: "all", created_older_than: 30).keys).to match_array(%w[MLBT1 MLBT3])
    expect(items(kind: "traditional", sales: "25-49").keys).to eq([ "MLBT1" ])
  end

  it "Promoções e Anúncios usam a mesma regra de sincronização" do
    expect(Painel::CatalogSync.for(account).map).to eq("MLBT1" => [ "MLBC1" ], "MLBT2" => [ "MLBC2" ])
  end

  describe "excluir tradicional sincronizado" do
    before { allow(Ml::OAuth).to receive(:refresh!) }

    def stub_delete(id, ok: true)
      if ok
        stub_request(:put, "#{ml}/items/#{id}").to_return(status: 200, body: "{}")
      else
        stub_request(:put, "#{ml}/items/#{id}").to_return(status: 400, body: { message: "Validation error", cause: [ { message: "Item cannot be closed" } ] }.to_json)
        stub_request(:get, %r{#{ml}/items/#{id}\?}).to_return(status: 200, body: { id: id, status: "active" }.to_json)
      end
    end

    it "a prévia lista os catálogos que sairão junto" do
      get "/api/items/delete_preview", params: { account_id: account.id, item_ids: %w[MLBT1 MLBT3 MLBC3] }, headers: auth_headers(member)
      expect(json["linked"]).to eq([ { "item_id" => "MLBT1", "catalogs" => [ "MLBC1" ] } ])
    end

    it "sem with_catalog recusa e não chama o ML" do
      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: [ "MLBT1" ], confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].join).to include("MLBT1 (catálogo MLBC1)")
      expect(a_request(:put, %r{#{ml}/items/})).not_to have_been_made
    end

    it "com with_catalog exclui o catálogo primeiro e depois o tradicional, com resultado de cada um" do
      [ "MLBC1", "MLBT1", "MLBT3" ].each { |id| stub_delete(id) }
      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: %w[MLBT1 MLBT3], confirm: true, with_catalog: true }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json["results"].map { |r| [ r["item_id"], r["ok"], r["catalog_of"] ] }).to eq([ [ "MLBC1", true, "MLBT1" ], [ "MLBT1", true, nil ], [ "MLBT3", true, nil ] ])
      expect(json["message"]).to eq("3 anúncio(s) excluído(s) do Mercado Livre.")
      expect(account.ml_items.where(item_id: %w[MLBC1 MLBT1 MLBT3]).pluck(:status).uniq).to eq([ "closed" ])
      expect(account.ml_items.find_by(item_id: "MLBC2").status).to eq("active")
    end

    it "catálogo também selecionado sai uma vez só, junto com o tradicional" do
      [ "MLBC1", "MLBT1" ].each { |id| stub_delete(id) }
      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: %w[MLBT1 MLBC1], confirm: true, with_catalog: true }, headers: auth_headers(admin)
      expect(json["results"].map { |r| r["item_id"] }).to eq(%w[MLBC1 MLBT1])
      expect(account.ml_item_edits.where(kind: "exclusao").count).to eq(2)
    end

    it "se o ML recusar o catálogo, o tradicional fica" do
      stub_delete("MLBC1", ok: false)
      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: [ "MLBT1" ], confirm: true, with_catalog: true }, headers: auth_headers(admin)
      results = json["results"].index_by { |r| r["item_id"] }
      expect(results["MLBC1"]).to include("ok" => false, "catalog_of" => "MLBT1")
      expect(results["MLBT1"]["ok"]).to be(false)
      expect(results["MLBT1"]["message"]).to include("catálogo sincronizado não pôde ser excluído")
      expect(a_request(:put, "#{ml}/items/MLBT1")).not_to have_been_made
      expect(account.ml_items.find_by(item_id: "MLBT1").status).to eq("active")
    end

    it "catálogo já finalizado não entra" do
      account.ml_items.find_by(item_id: "MLBC1").update!(status: "closed")
      get "/api/items/delete_preview", params: { account_id: account.id, item_ids: [ "MLBT1" ] }, headers: auth_headers(member)
      expect(json["linked"]).to eq([])
    end
  end
end
