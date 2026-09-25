require "rails_helper"

RSpec.describe Painel::ItemQuery do
  let(:account) { create(:ml_account) }

  def call(params = {})
    described_class.call(account, ActionController::Parameters.new(params))
  end

  describe "status" do
    it "ativos por padrão" do
      active = create(:item_metric, ml_account: account, status: "active")
      create(:item_metric, ml_account: account, status: "paused")

      expect(call[:items].map { |i| i[:id] }).to eq([ active.item_id ])
    end

    it "closed agrupa closed, inactive e under_review" do
      closed = create(:item_metric, ml_account: account, status: "closed", revenue_30d: 10)
      inactive = create(:item_metric, ml_account: account, status: "inactive", revenue_30d: 10)
      under_review = create(:item_metric, ml_account: account, status: "under_review")
      create(:item_metric, ml_account: account, status: "active")

      result = call(status: "closed")

      expect(result[:items].map { |i| i[:id] }).to match_array([ closed.item_id, inactive.item_id, under_review.item_id ])
    end

    it "all traz tudo" do
      create(:item_metric, ml_account: account, status: "active")
      create(:item_metric, ml_account: account, status: "closed")

      expect(call(status: "all")[:total]).to eq(2)
    end

    it "status_counts não é afetado pelos demais filtros" do
      create(:item_metric, ml_account: account, status: "active", title: "Camiseta Azul")
      create(:item_metric, ml_account: account, status: "active", title: "Caneca Branca")
      create(:item_metric, ml_account: account, status: "paused", title: "Boné Verde")

      result = call(q: "Azul")

      expect(result[:items].size).to eq(1)
      expect(result[:status_counts]).to eq(active: 2, paused: 1, closed: 0, all: 3)
    end
  end

  it "alert aplica a regra e ignora o parâmetro status" do
    target = create(:item_metric, ml_account: account, status: "under_review")
    create(:item_metric, ml_account: account, status: "active")

    result = call(status: "paused", alert: "under_review")

    expect(result[:items].map { |i| i[:id] }).to eq([ target.item_id ])
    expect(result[:active_filter]).to eq(alert: { key: "under_review", title: "Em revisão pelo Mercado Livre" })
  end

  it "id traz só aquele anúncio e ignora os demais filtros" do
    target = create(:item_metric, ml_account: account, status: "paused")
    create(:item_metric, ml_account: account, status: "active")

    result = call(id: target.item_id, q: "não bate com nada")

    expect(result[:items].map { |i| i[:id] }).to eq([ target.item_id ])
    expect(result[:total]).to eq(1)
  end

  it "type filtra Premium/Clássico" do
    premium = create(:item_metric, ml_account: account, status: "active", listing_type: "P")
    create(:item_metric, ml_account: account, status: "active", listing_type: "C")

    expect(call(type: "P")[:items].map { |i| i[:id] }).to eq([ premium.item_id ])
  end

  it "shipping filtra full/non_full" do
    full = create(:item_metric, ml_account: account, status: "active", full: true)
    create(:item_metric, ml_account: account, status: "active", full: false)

    expect(call(shipping: "full")[:items].map { |i| i[:id] }).to eq([ full.item_id ])
  end

  it "f[sku] = 'sem sku' traz os sem SKU" do
    no_sku = create(:item_metric, ml_account: account, status: "active", sku: nil)
    create(:item_metric, ml_account: account, status: "active", sku: "ABC")

    expect(call(f: { sku: "sem sku" })[:items].map { |i| i[:id] }).to eq([ no_sku.item_id ])
  end

  it "f[units_delta] só considera quem vendeu em alguma das duas semanas (nulo nunca passa)" do
    sold = create(:item_metric, ml_account: account, status: "active", units_delta: 5)
    create(:item_metric, ml_account: account, status: "active", units_delta: nil)

    expect(call(f: { units_delta: ">0" })[:items].map { |i| i[:id] }).to eq([ sold.item_id ])
  end

  it "expressão inválida some do filtro e vai pra invalid_filters" do
    create(:item_metric, ml_account: account, status: "active", price: 10)

    result = call(f: { price: "abc" })

    expect(result[:invalid_filters]).to eq([ "price" ])
    expect(result[:total]).to eq(1)
  end

  it "active_filters_count conta q, type, shipping, alert e cada f[] preenchido" do
    create(:item_metric, ml_account: account, status: "active")

    result = call(q: "x", type: "P", shipping: "full", f: { price: ">10", sku: "abc" })

    expect(result[:active_filters_count]).to eq(5)
  end

  describe "ordenação" do
    it "ordena texto pela collation pt-BR (Água entre abacate e banana)" do
      create(:item_metric, ml_account: account, status: "active", title: "abacate")
      create(:item_metric, ml_account: account, status: "active", title: "Água")
      create(:item_metric, ml_account: account, status: "active", title: "banana")

      expect(call(sort: "title")[:items].map { |i| i[:title] }).to eq([ "abacate", "Água", "banana" ])
    end

    it "dir inválido cai no padrão da coluna" do
      create(:item_metric, ml_account: account, status: "active", title: "b")
      create(:item_metric, ml_account: account, status: "active", title: "a")

      result = call(sort: "title", dir: "sideways")

      expect(result[:dir]).to eq("asc")
      expect(result[:items].map { |i| i[:title] }).to eq([ "a", "b" ])
    end

    it "padrão é units_7d decrescente" do
      result = call
      expect(result[:sort]).to eq(:units_7d)
      expect(result[:dir]).to eq("desc")
    end

    it "nulos sempre no fim, nas duas direções" do
      with_value = create(:item_metric, ml_account: account, status: "active", coverage_days: 5)
      without_value = create(:item_metric, ml_account: account, status: "active", coverage_days: nil)

      asc = call(sort: "coverage_days", dir: "asc")
      desc = call(sort: "coverage_days", dir: "desc")

      expect(asc[:items].map { |i| i[:id] }).to eq([ with_value.item_id, without_value.item_id ])
      expect(desc[:items].map { |i| i[:id] }).to eq([ with_value.item_id, without_value.item_id ])
    end

    it "desempate por visits_7d decrescente, depois item_id" do
      higher_visits = create(:item_metric, ml_account: account, status: "active", units_7d: 5, visits_7d: 50)
      lower_visits = create(:item_metric, ml_account: account, status: "active", units_7d: 5, visits_7d: 10)

      expect(call[:items].map { |i| i[:id] }).to eq([ higher_visits.item_id, lower_visits.item_id ])
    end
  end

  describe "paginação" do
    it "pagina e limita per_page a 200" do
      create_list(:item_metric, 3, ml_account: account, status: "active")

      result = call(page: "2", per_page: "2")

      expect(result[:page]).to eq(2)
      expect(result[:per_page]).to eq(2)
      expect(result[:items].size).to eq(1)
      expect(result[:total]).to eq(3)
      expect(call(per_page: "9999")[:per_page]).to eq(200)
    end
  end

  describe "campos derivados da linha" do
    it "monta discount_pct, stock_state, coverage_state, quality_state, units_delta_direction, quality_actions e links" do
      create(:ml_item, ml_account: account, item_id: "MLB1", quality_level: "yellow",
        quality_pending: [ { "area" => "images", "key" => "main", "title" => "Foto", "label" => "Troque a foto", "mode" => "recommended" } ])
      create(:item_metric, ml_account: account, item_id: "MLB1", status: "active", price: 80, original_price: 100,
        stock: 0, quality_score: 65, coverage_days: 10, units_delta: -2)

      row = call[:items].first

      expect(row[:discount_pct]).to eq(20)
      expect(row[:stock_state]).to eq("bad")
      expect(row[:coverage_state]).to eq("bad")
      expect(row[:quality_state]).to eq("warn")
      expect(row[:units_delta_direction]).to eq("down")
      expect(row[:quality_level]).to eq("yellow")
      expect(row[:quality_actions]).to eq([ { title: "Foto", label: "Troque a foto" } ])
      expect(row[:links][:public]).to eq("https://produto.mercadolivre.com.br/MLB-1")
      expect(row[:lean]).to be false
    end

    it "payload enxuto pra closed/inactive sem faturamento nos últimos 60 dias" do
      create(:item_metric, ml_account: account, status: "closed", title: "Sem venda", sku: "X1", price: 10.0,
        stock: 3, revenue_30d: 0, prev_revenue_30d: 0, units_7d: 3, quality_score: 90)

      row = call(status: "all")[:items].first

      expect(row[:lean]).to be true
      expect(row).to include(title: "Sem venda", sku: "X1", price: 10.0, stock: 3)
      expect(row[:quality_score]).to be_nil
      expect(row[:units_7d]).to be_nil
      expect(row[:quality_actions]).to eq([])
      expect(row[:alert_keys]).to eq([])
    end

    it "closed com faturamento nos últimos 60 dias não é lean" do
      create(:item_metric, ml_account: account, status: "closed", revenue_30d: 100, prev_revenue_30d: 0)

      expect(call(status: "all")[:items].first[:lean]).to be false
    end
  end
end
