require "rails_helper"

RSpec.describe "/api/ads", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company) }

  def campaign(id, name: "Camp #{id}", status: "active", acos_target: 10.0)
    MlAdCampaign.create!(ml_account_id: account.id, campaign_id: id, name: name, status: status, strategy: "PROFITABILITY",
      acos_target: acos_target, daily_budget: 50)
  end

  def day(campaign_id, date, cost:, amount:, clicks: 10, prints: 1000, units: 1)
    MlAdDailyMetric.create!(ml_account_id: account.id, campaign_id: campaign_id, date: date, cost: cost, total_amount: amount,
      clicks: clicks, prints: prints, units: units)
  end

  def ad(item_id, campaign_id, metrics, title: "Produto #{item_id}", status: "active")
    MlAdItem.create!(ml_account_id: account.id, item_id: item_id, campaign_id: campaign_id, title: title, status: status, price: 50,
      metrics: { "30d" => metrics, "7d" => metrics, "90d" => metrics }, synced_at: Time.current)
  end

  it "resumo, campanhas e série diária, com as métricas recalculadas (ACOS, ROAS, CTR, CPC, conversão)" do
    campaign(1)
    campaign(2, acos_target: 5.0)
    day(1, Date.current - 1, cost: 10, amount: 200, clicks: 50, prints: 5000, units: 4)
    day(2, Date.current - 2, cost: 30, amount: 300, clicks: 50, prints: 5000, units: 6)

    get "/api/ads", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(numeric_strings(json)).to be_empty
    expect(json["summary"]).to include("cost" => 40.0, "total_amount" => 500.0, "acos" => 8.0, "roas" => 12.5, "clicks" => 100,
      "prints" => 10_000, "ctr" => 1.0, "cpc" => 0.4, "cvr" => 10.0, "units" => 10)
    by_name = json["campaigns"].to_h { |c| [ c["name"], c ] }
    expect(by_name["Camp 1"]).to include("acos_state" => "ok")        # ACOS 5 ≤ meta 10
    expect(by_name["Camp 2"]).to include("acos_state" => "bad")       # ACOS 10 > meta 5 × 1,2
    expect(json["daily"].size).to eq(30)
    expect(json["daily"].sum { |d| d["cost"] }).to eq(40.0)
  end

  it "período muda o recorte e compara com o período anterior quando há dados" do
    campaign(1)
    day(1, Date.current - 2, cost: 10, amount: 100)
    day(1, Date.current - 20, cost: 50, amount: 100)
    day(1, Date.current - 40, cost: 7, amount: 100)

    get "/api/ads", params: { account_id: account.id, period: "7d" }, headers: auth_headers(member)
    expect(json["summary"]["cost"]).to eq(10.0)

    get "/api/ads", params: { account_id: account.id, period: "30d" }, headers: auth_headers(member)
    expect(json["summary"]["cost"]).to eq(60.0)
    expect(json["previous"]["cost"]).to eq(7.0)
  end

  it "hoje e ontem mostram só o dia, com comparação com o dia anterior" do
    campaign(1)
    day(1, Date.current, cost: 4, amount: 40)
    day(1, Date.current - 1, cost: 10, amount: 100)
    day(1, Date.current - 2, cost: 8, amount: 80)

    get "/api/ads", params: { account_id: account.id, period: "today" }, headers: auth_headers(member)
    expect(json["period"]).to include("preset" => "today", "days" => 1)
    expect(json["summary"]["cost"]).to eq(4.0)
    expect(json["previous"]["cost"]).to eq(10.0)
    expect(json["daily"].size).to eq(1)

    get "/api/ads", params: { account_id: account.id, period: "yesterday" }, headers: auth_headers(member)
    expect(json["period"]).to include("preset" => "yesterday", "days" => 1)
    expect(json["summary"]["cost"]).to eq(10.0)
    expect(json["previous"]["cost"]).to eq(8.0)
  end

  it "datas escolhidas: recorte pelo período e limite de 90 dias" do
    campaign(1)
    day(1, Date.current - 5, cost: 10, amount: 100)
    day(1, Date.current - 6, cost: 3, amount: 30)
    day(1, Date.current - 20, cost: 50, amount: 500)

    get "/api/ads", params: { account_id: account.id, from: (Date.current - 6).iso8601, to: (Date.current - 5).iso8601 },
      headers: auth_headers(member)
    expect(json["period"]).to include("preset" => "custom", "days" => 2)
    expect(json["summary"]["cost"]).to eq(13.0)

    get "/api/ads", params: { account_id: account.id, from: (Date.current - 300).iso8601, to: Date.current.iso8601 },
      headers: auth_headers(member)
    expect(json["period"]["days"]).to eq(90)
  end

  it "anúncios de um período que não está guardado (hoje, ontem, datas) são consultados no Mercado Livre na hora" do
    campaign(1)
    ad("MLB1", 1, { "cost" => 999.0 }, title: "Batom")
    allow(Ml::OAuth).to receive(:refresh!)
    allow(Ml::Sync::Ads).to receive(:live_items)
      .and_return({ "MLB1" => { "cost" => 7.0, "total_amount" => 70.0, "units_quantity" => 1, "clicks" => 3, "prints" => 90 } })

    get "/api/ads/items", params: { account_id: account.id, period: "today" }, headers: auth_headers(member)

    expect(json).to include("live" => true, "live_error" => false, "window" => "custom")
    expect(json["items"].first["metrics"]).to include("cost" => 7.0, "total_amount" => 70.0, "acos" => 10.0)
    expect(Ml::Sync::Ads).to have_received(:live_items).once
  end

  it "se o Mercado Livre não responder, os anúncios vêm zerados e a resposta avisa" do
    campaign(1)
    ad("MLB1", 1, { "cost" => 999.0 })
    allow(Ml::OAuth).to receive(:refresh!)
    allow(Ml::Sync::Ads).to receive(:live_items).and_return(nil)

    get "/api/ads/items", params: { account_id: account.id, period: "yesterday" }, headers: auth_headers(member)

    expect(json).to include("live" => true, "live_error" => true)
    expect(json["items"].first["metrics"]["cost"]).to eq(0.0)
  end

  it "7, 30 e 90 dias usam as janelas guardadas, sem chamar o Mercado Livre" do
    campaign(1)
    ad("MLB1", 1, { "cost" => 5.0 })
    allow(Ml::Sync::Ads).to receive(:live_items)

    get "/api/ads/items", params: { account_id: account.id, period: "30d" }, headers: auth_headers(member)

    expect(json).to include("live" => false, "window" => "30d")
    expect(Ml::Sync::Ads).not_to have_received(:live_items)
  end

  it "campanha sem venda fica com ACOS nulo, sem dividir por zero" do
    campaign(1)
    day(1, Date.current - 1, cost: 10, amount: 0, clicks: 0, units: 0)

    get "/api/ads", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["summary"]).to include("acos" => nil, "cvr" => nil, "cpc" => nil)
    expect(json["campaigns"].first["acos_state"]).to eq("bad")
  end

  it "lista de anúncios: filtros, busca, ordenação, sinais e totais" do
    campaign(1, acos_target: 10.0)
    campaign(2, status: "paused")
    ad("MLB1", 1, { "cost" => 100.0, "total_amount" => 2000.0, "units_quantity" => 20, "clicks" => 100, "prints" => 1000 }, title: "Batom Rosa")
    ad("MLB2", 1, { "cost" => 50.0, "total_amount" => 0.0, "units_quantity" => 0, "clicks" => 40, "prints" => 900 }, title: "Gloss")
    ad("MLB3", 1, { "cost" => 30.0, "total_amount" => 150.0, "units_quantity" => 2, "clicks" => 30, "prints" => 500 }, title: "Base")
    ad("MLB4", 2, { "cost" => 0.0 }, title: "Rímel", status: "paused")

    get "/api/ads/items", params: { account_id: account.id, sort: "cost" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq(%w[MLB1 MLB2 MLB3 MLB4])
    expect(json["totals"]).to include("cost" => 180.0, "total_amount" => 2150.0)
    expect(json["flags"]).to include("sem_venda" => 1, "bom" => 1, "acos_alto" => 1)
    first = json["items"].first
    expect(first["flag"]).to include("key" => "bom")
    expect(first["metrics"]).to include("acos" => 5.0, "roas" => 20.0)

    get "/api/ads/items", params: { account_id: account.id, campaign_id: 2 }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLB4" ])

    get "/api/ads/items", params: { account_id: account.id, q: "gloss" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLB2" ])

    get "/api/ads/items", params: { account_id: account.id, flag: "sem_venda" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }).to eq([ "MLB2" ])

    get "/api/ads/items", params: { account_id: account.id, sort: "acos", dir: "asc" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["item_id"] }.first(2)).to eq(%w[MLB1 MLB3]) # sem ACOS vai para o fim
  end

  it "anúncio de campanha que não existe mais aparece como encerrada" do
    ad("MLB9", 999, { "cost" => 1.0 })

    get "/api/ads/items", params: { account_id: account.id }, headers: auth_headers(member)

    expect(json["items"].first["campaign"]).to include("name" => "Campanha encerrada")
  end

  it "conta de outra empresa é 404 e exige login" do
    other = create(:ml_account)
    get "/api/ads", params: { account_id: other.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:not_found)

    get "/api/ads", params: { account_id: account.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it "só administrador pede a leitura de novo (job na fila)" do
    post "/api/ads/sync", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    expect do
      post "/api/ads/sync", params: { account_id: account.id }, headers: auth_headers(admin)
    end.to have_enqueued_job(Ml::AdsSyncJob).with(account.id)
    expect(response).to have_http_status(:accepted)
  end

  it "período mês até hoje: do dia 1º do mês corrente até hoje" do
    travel_to(Time.find_zone("America/Sao_Paulo").parse("2026-10-30 15:00")) do
      get "/api/ads", params: { account_id: account.id, period: "mtd" }, headers: auth_headers(member)
    end

    expect(response).to have_http_status(:ok)
    expect(json["period"]["preset"]).to eq("mtd")
    expect(json["period"]["from"]).to start_with("2026-10-01")
    expect(json["period"]["to"]).to start_with("2026-10-30")
  end

  describe "GET /api/ads/analysis" do
    def item_day(item_id, campaign_id, date, cost:, amount:, clicks: 10, prints: 1000, units: 1)
      MlAdItemDaily.create!(ml_account_id: account.id, item_id: item_id, campaign_id: campaign_id, date: date, cost: cost, total_amount: amount,
        clicks: clicks, prints: prints, units: units)
    end

    it "saúde com TACOS, famílias com sinais, intocáveis e a fila por dinheiro em jogo" do
      campaign(1, name: "Maquiagens")
      MlAdCampaign.where(campaign_id: 1).update_all(auction: { "7d" => { "impression_share" => 0.5, "lost_by_budget" => 0.3, "lost_by_ad_rank" => 0.2, "acos_benchmark" => 12.0, "consistent" => true } })
      yesterday = Date.current - 1
      # orgânico da conta no período
      MlAdDailyMetric.create!(ml_account_id: account.id, campaign_id: 1, date: yesterday, cost: 0, total_amount: 0, organic_amount: 1000)
      # família A: um anúncio ativo (vende) e um fora do ar com receita no período
      ad("MLB1", 1, {}, title: "Batom A ativo").update!(family_id: "F1", family_name: "Batom Vegano", date_created: 90.days.ago)
      ad("MLB2", 1, {}, title: "Batom A hold", status: "hold").update!(family_id: "F1", date_created: 90.days.ago)
      item_day("MLB1", 1, yesterday, cost: 20, amount: 300, clicks: 40, prints: 2000, units: 3)
      item_day("MLB2", 1, yesterday - 2, cost: 5, amount: 150)
      # família B: gastou e não vendeu
      ad("MLB3", 1, {}, title: "Pincel").update!(family_id: "F2", family_name: "Pincel", date_created: 90.days.ago)
      item_day("MLB3", 1, yesterday, cost: 12, amount: 0, clicks: 3, prints: 600, units: 0)
      # família C: anúncio novo (intocável)
      ad("MLB4", 1, {}, title: "Novo").update!(family_id: "F3", family_name: "Novo", date_created: 5.days.ago)
      item_day("MLB4", 1, yesterday, cost: 15, amount: 0)

      get "/api/ads/analysis", params: { account_id: account.id }, headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      h = json["health"]
      expect(h).to include("cost" => 52.0, "revenue" => 450.0, "organic" => 1000.0)
      expect(h["tacos"]).to be_within(0.01).of(52.0 / 1450 * 100)
      fam = json["families"].to_h { |f| [ f["key"], f ] }
      expect(fam["F1"]["signals"].map { |s| s["type"] }).to include("saiu_do_ar_com_historico")
      expect(fam["F2"]["signals"].map { |s| s["type"] }).to eq([ "gasto_sem_receita" ])
      expect(fam["F3"]["untouchable"]["reason"]).to include("em maturação")
      expect(json["untouchables"].map { |u| u["key"] }).to eq([ "F3" ])
      classes = json["queue"].map { |q| q["class"] }
      expect(classes.first).to eq("destravar") # receita parada vem antes do desperdício
      expect(json["queue"].first).to include("title" => "Batom Vegano", "value" => 150.0)
      expect(json["queue"].find { |q| q["class"] == "desperdicio" }).to include("title" => "Pincel", "value" => 12.0)
      expect(json["queue"].find { |q| q["class"] == "orcamento" }).to include("title" => "Campanha Maquiagens") # perde 30% por orçamento com ROAS acima da referência
      expect(json["closing"]["text"]).to include("TACOS")
    end

    it "diagnostica uma família e uma campanha, e guarda decisões com o antes e o depois" do
      campaign(1, name: "Maquiagens")
      MlAdCampaign.where(campaign_id: 1).update_all(auction: { "7d" => { "impression_share" => 0.1, "lost_by_budget" => 0.05, "lost_by_ad_rank" => 0.85, "acos_benchmark" => 12.0, "consistent" => true } }, daily_budget: 50)
      yesterday = Date.current - 1
      ad("MLB3", 1, {}, title: "Pincel").update!(family_id: "F2", family_name: "Pincel", date_created: 90.days.ago)
      item_day("MLB3", 1, yesterday, cost: 12, amount: 0, clicks: 3, prints: 600, units: 0)

      get "/api/ads/diagnosis", params: { account_id: account.id, family: "F2" }, headers: auth_headers(member)
      expect(json).to include("symptom" => "gasta_e_nao_vende")
      expect(json["avoid"]).to include("Manter o anúncio ativo esperando melhora natural.")
      expect(json["actions"].first["action"]).to include("Comparar preço")

      get "/api/ads/diagnosis", params: { account_id: account.id, campaign_id: 1 }, headers: auth_headers(member)
      expect(json).to include("symptom" => "perde_por_ad_rank")
      expect(json["avoid"].first).to include("Aumentar o orçamento")

      post "/api/ads/decisions", params: { account_id: account.id, key: "F2", signal: "gasto_sem_receita", status: "feito" }, headers: auth_headers(member)
      expect(response).to have_http_status(:forbidden)
      post "/api/ads/decisions", params: { account_id: account.id, key: "F2", signal: "gasto_sem_receita", status: "feito" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
      expect(json).to include("status" => "feito", "class" => "desperdicio", "title" => "Pincel")
      expect(json["before"]).to include("cost" => 12.0)

      get "/api/ads/analysis", params: { account_id: account.id }, headers: auth_headers(member)
      expect(json["decisions"].size).to eq(1)
      expect(json["decisions"].first["after"]).to be_nil # ainda não passou um dia fechado
      expect(json["queue"].find { |q| q["key"] == "F2" }["decided"]).to include("status" => "feito")

      delete "/api/ads/decisions/#{MlAdDecision.last.id}", params: { account_id: account.id }, headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
    end

    it "respeita o máximo de ações e manda o resto para a próxima rodada" do
      campaign(1)
      yesterday = Date.current - 1
      3.times do |i|
        ad("MLB#{i}", 1, {}, title: "P#{i}").update!(family_id: "G#{i}", family_name: "Família #{i}", date_created: 90.days.ago)
        item_day("MLB#{i}", 1, yesterday, cost: 20 + i, amount: 0, clicks: 5, prints: 600)
      end

      get "/api/ads/analysis", params: { account_id: account.id, max_actions: 2 }, headers: auth_headers(member)

      expect(json["queue"].size).to eq(2)
      expect(json["queue"].map { |q| q["value"] }).to eq([ 22.0, 21.0 ])
      expect(json["next_round"].size).to eq(1)
    end

    it "estrutura de campanhas: dividir família dominante, ativar fora de campanha, reativar pausado e respeitar o limite diário" do
      company.update!(ads_daily_budget_max: 60)
      yesterday = Date.current - 1
      # campanha compartilhada (3 famílias) perdendo por classificação; família F1 concentra a verba com ROAS alto
      campaign(1, name: "Geral")
      MlAdCampaign.where(campaign_id: 1).update_all(auction: { "7d" => { "impression_share" => 0.3, "lost_by_budget" => 0.1, "lost_by_ad_rank" => 0.6, "consistent" => true } })
      %w[F1 F2 F3].each_with_index do |f, i|
        ad("MLB#{i + 1}", 1, {}, title: "Produto #{f}").update!(family_id: f, family_name: "Família #{f}", date_created: 90.days.ago)
      end
      item_day("MLB1", 1, yesterday, cost: 80, amount: 1600, clicks: 200, prints: 5000, units: 20)
      item_day("MLB2", 1, yesterday, cost: 10, amount: 100, clicks: 40, prints: 1000, units: 2)
      item_day("MLB3", 1, yesterday, cost: 10, amount: 90, clicks: 40, prints: 1000, units: 2)
      # fora de campanha (idle) vendendo sozinho, com margem e estoque
      ad("MLB9", nil, {}, title: "Sozinho", status: "idle")
      create(:item_metric, ml_account: account, item_id: "MLB9", sku: "SKU-9", price: 100, units_30d: 6, revenue_30d: 600, stock: 12)
      create(:ml_item, ml_account: account, item_id: "MLB9", fee_now: 16.5, ship_cost: 8.0)
      MlCost.create!(company: company, sku: "SKU-9", cost: 30, extra: 0)
      # pausado na publicidade que rendia nos 90 dias
      ad("MLB8", 1, { "cost" => 90, "total_amount" => 900, "units_quantity" => 9 }, title: "Pausado", status: "paused")
      create(:item_metric, ml_account: account, item_id: "MLB8", sku: "SKU-8", price: 100, stock: 5)
      create(:ml_item, ml_account: account, item_id: "MLB8", fee_now: 16.5, ship_cost: 8.0)
      MlCost.create!(company: company, sku: "SKU-8", cost: 30, extra: 0)

      get "/api/ads/analysis", params: { account_id: account.id }, headers: auth_headers(member)

      st = json["structure"]
      expect(st["daily_max"]).to eq(60.0)
      expect(st["current_daily"]).to eq(50.0)
      by_type = st["suggestions"].group_by { |x| x["type"] }
      split = by_type.fetch("dividir").first
      expect(split).to include("title" => "Família F1", "from_campaign" => "Geral", "daily_budget" => 40, "within_limit" => true)
      expect(split["to_campaign"]).to include("exclusiva")
      expect(split["rationale"]).to include("80%").and include("perde 60% por classificação")
      activate = by_type.fetch("ativar").first
      expect(activate).to include("item_ids" => [ "MLB9" ], "daily_budget" => 1, "within_limit" => true, "from_campaign" => nil)
      expect(activate["rationale"]).to include("Vende 6 un. em 30 dias sem Ads")
      reactivate = by_type.fetch("reativar").first
      expect(reactivate).to include("item_ids" => [ "MLB8" ], "to_campaign" => "Geral", "within_limit" => true)
      expect(reactivate["rationale"]).to include("ROAS 10.0")
      # dividir só realoca (sai dos R$ 50 da Geral); ativar e reativar são dinheiro novo dentro do teto de R$ 60
      expect(st["plan"]).to include("reallocated_daily" => 40.0, "fits" => true)
      expect(st["plan"]["after_daily"]).to be <= 60.0
      expect(by_type).not_to have_key("reduzir")
    end

    it "sem limite diário o plano avisa; com teto apertado o dinheiro novo fica marcado e uma campanha abaixo do equilíbrio cede verba" do
      yesterday = Date.current - 1
      campaign(1, name: "Ruim")
      ad("MLB1", 1, {}, title: "Perde").update!(family_id: "F1", family_name: "Perde", date_created: 90.days.ago)
      create(:item_metric, ml_account: account, item_id: "MLB1", sku: "SKU-1", price: 100)
      create(:ml_item, ml_account: account, item_id: "MLB1", fee_now: 16.5, ship_cost: 8.0)
      MlCost.create!(company: company, sku: "SKU-1", cost: 60, extra: 0) # margem baixa → equilíbrio alto
      item_day("MLB1", 1, yesterday, cost: 50, amount: 60, clicks: 40, prints: 1000, units: 1)
      ad("MLB9", nil, {}, title: "Sozinho", status: "idle")
      create(:item_metric, ml_account: account, item_id: "MLB9", sku: "SKU-9", price: 100, units_30d: 30, revenue_30d: 3000, stock: 12)
      create(:ml_item, ml_account: account, item_id: "MLB9", fee_now: 16.5, ship_cost: 8.0)
      MlCost.create!(company: company, sku: "SKU-9", cost: 30, extra: 0)

      get "/api/ads/analysis", params: { account_id: account.id }, headers: auth_headers(member)
      expect(json["structure"]["plan"]["note"]).to include("Configurações")
      expect(json["structure"]["suggestions"].map { |x| x["type"] }).to eq([ "ativar" ])

      company.update!(ads_daily_budget_max: 50) # já está no teto: o anúncio novo (R$ 4/dia) só cabe com redução
      get "/api/ads/analysis", params: { account_id: account.id }, headers: auth_headers(member)
      st = json["structure"]
      activate = st["suggestions"].find { |x| x["type"] == "ativar" }
      reduce = st["suggestions"].find { |x| x["type"] == "reduzir" }
      expect(reduce).to include("from_campaign" => "Ruim", "daily_budget" => -25) # ROAS 1,2 < metade do equilíbrio: cede metade
      expect(activate).to include("within_limit" => true)
      expect(activate["note"]).to include("redução sugerida em Ruim")
      expect(st["plan"]).to include("after_daily" => 29.0, "fits" => true)
    end
  end
end
