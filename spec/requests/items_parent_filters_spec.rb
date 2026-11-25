require "rails_helper"

# Anúncios › filtros "criados há mais de" e "Quantidade de Vendas" pelo anúncio pai (pedido do usuário em 25/11/2026):
# com variações (cada variação é um anúncio, o pai é a família), a tabela mostra só o pai, com as vendas somadas de todas
# as variações e a data de criação do mais antigo. Excluir o pai leva todas as variações. O ML é sempre simulado.
RSpec.describe "/api/items: filtros pelo anúncio pai", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }

  def listing(id, sold:, family: nil, status: "active", created: 1.year.ago, type: "gold_special", catalog: false)
    create(:item_metric, ml_account: account, item_id: id, title: "Anúncio #{id}", status: status, catalog: catalog)
    create(:ml_item, ml_account: account, item_id: id, title: "Anúncio #{id}", status: status, sold_quantity: sold, family_id: family,
                     listing_type_id: type, date_created: created, catalog_listing: catalog)
  end

  before do
    # família A: 1000 + 100 + 50 + três sem vendas = 1150
    listing("MLBA1", sold: 1000, family: "FA")
    listing("MLBA2", sold: 100, family: "FA", status: "paused")
    listing("MLBA3", sold: 50, family: "FA")
    %w[MLBA4 MLBA5 MLBA6].each { |id| listing(id, sold: 0, family: "FA", status: "paused") }
    # família B: 3 + 4 = 7
    listing("MLBB1", sold: 3, family: "FB", status: "paused")
    listing("MLBB2", sold: 4, family: "FB", status: "paused")
    # família C: nenhuma variação vendeu
    listing("MLBC1", sold: 0, family: "FC", created: 10.days.ago)
    listing("MLBC2", sold: 0, family: "FC", created: 2.years.ago)
    # anúncio sozinho, e um Clássico da família B (outro tipo = outro pai)
    listing("MLBS", sold: 0)
    listing("MLBB9", sold: 0, family: "FB", type: "gold_pro")
  end

  def rows(params = {})
    get "/api/items", params: { account_id: account.id, status: "all" }.merge(params), headers: auth_headers(member)
    json["items"].index_by { |i| i["id"] }
  end

  it "sem vendas: só pais sem venda em nenhuma variação" do
    list = rows(sales: "none")
    expect(list.keys).to match_array(%w[MLBC1 MLBS MLBB9]) # nada da família A nem da B (7 vendas)
    expect(json["grouped_by_parent"]).to be(true)
    expect(json["status_counts"]["all"]).to eq(3)
    expect(list["MLBC1"]["family"]).to include("count" => 2, "sold_total" => 0, "item_ids" => %w[MLBC1 MLBC2])
    expect(list["MLBS"]["family"]).to be_nil
  end

  it "faixas pela soma das variações; o pai é a variação ativa que mais vende" do
    expect(rows(sales: "5-9").keys).to eq([ "MLBB2" ]) # 3 + 4 = 7; ambas pausadas, a que mais vendeu
    expect(json["items"].first["family"]).to include("count" => 2, "sold_total" => 7)
    expect(rows(sales: "1000-4999").keys).to eq([ "MLBA1" ])
    expect(json["items"].first["family"]).to include("count" => 6, "sold_total" => 1150)
    expect(rows(sales: "50-99").keys).to eq([]) # nenhuma variação sozinha conta
  end

  it "criação pelo anúncio mais antigo da família, cumulativo com vendas" do
    expect(rows(created_older_than: 365, sales: "none").keys).to match_array(%w[MLBC1 MLBS MLBB9]) # FC tem um de 2 anos
    expect(rows(created_older_than: 600, sales: "none").keys).to eq([ "MLBC1" ])
  end

  it "sem os filtros, cada variação continua na tabela" do
    expect(rows.size).to eq(12)
    expect(json["grouped_by_parent"]).to be(false)
    expect(json["items"].map { |i| i["family"] }.uniq).to eq([ nil ])
  end

  describe "excluir o pai" do
    before { allow(Ml::OAuth).to receive(:refresh!) }

    it "a prévia lista as variações que saem junto" do
      get "/api/items/delete_preview", params: { account_id: account.id, item_ids: %w[MLBC1 MLBS], with_variations: true }, headers: auth_headers(member)
      expect(json["item_ids"]).to eq(%w[MLBC1 MLBC2 MLBS])
      expect(json["variations"]).to eq([ { "item_id" => "MLBC1", "others" => [ "MLBC2" ] } ])
    end

    it "com with_variations exclui todas as variações da família" do
      stub = stub_request(:put, %r{#{ml}/items/MLBC[12]}).to_return(status: 200, body: "{}")
      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: [ "MLBC1" ], confirm: true, with_variations: true }, headers: auth_headers(admin)
      expect(json["results"].map { |r| [ r["item_id"], r["ok"] ] }).to eq([ [ "MLBC1", true ], [ "MLBC2", true ] ])
      expect(stub).to have_been_requested.times(4) # finalizar e marcar excluído, cada um
      expect(a_request(:put, %r{#{ml}/items/MLBS})).not_to have_been_made
    end

    it "sem with_variations só o anúncio escolhido" do
      stub_request(:put, "#{ml}/items/MLBC1").to_return(status: 200, body: "{}")
      post "/api/items/bulk_delete", params: { account_id: account.id, item_ids: [ "MLBC1" ], confirm: true }, headers: auth_headers(admin)
      expect(json["results"].map { |r| r["item_id"] }).to eq([ "MLBC1" ])
    end
  end
end
