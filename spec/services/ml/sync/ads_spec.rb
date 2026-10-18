require "rails_helper"

RSpec.describe Ml::Sync::Ads do
  let(:account) { create(:ml_account) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let(:today) { Date.new(2026, 10, 17) }
  let(:base) { "https://api.mercadolibre.com/advertising/MLB/advertisers/29660/product_ads" }

  def stub_advertiser
    stub_request(:get, "https://api.mercadolibre.com/advertising/advertisers").with(query: { product_id: "PADS" })
      .to_return(status: 200, body: { advertisers: [ { advertiser_id: 29_660, site_id: "MLB" } ] }.to_json)
  end

  def stub_campaigns
    stub_request(:get, "#{base}/campaigns/search").with(query: hash_including({})).to_return(status: 200, body: {
      paging: { total: 1, offset: 0, limit: 50 },
      results: [ { id: 111, name: "Maquiagens", status: "active", strategy: "PROFITABILITY", channel: "marketplace",
                   acos_target: 9.09, roas_target: 11.0, budget: 55.0, daily_budget: 110.0, automatic_budget: false,
                   date_created: "2026-08-03T16:20:40.000Z", last_updated: "2026-10-12T04:45:15.000Z" } ]
    }.to_json)
  end

  def stub_ads(window_params, results, total: results.size)
    stub_request(:get, "#{base}/ads/search").with(query: hash_including(window_params))
      .to_return(status: 200, body: { paging: { total: total, offset: 0, limit: 100 }, results: results }.to_json)
  end

  let(:ad) do
    { item_id: "MLB1", campaign_id: 111, ad_group_id: 9, title: "Batom", status: "active", price: 30.0, thumbnail: "http://x/t.jpg",
      permalink: "https://p", listing_type_id: "gold_special", logistic_type: "fulfillment", catalog_listing: false,
      buy_box_winner: false, recommended: false, has_discount: false, condition: "new", date_created: "2026-09-30T15:49:23Z",
      metrics: { clicks: 10, prints: 1000, cost: 5.0, total_amount: 60.0, units_quantity: 2 } }
  end

  it "grava campanhas, métricas diárias e anúncios com as janelas de 7, 30 e 90 dias" do
    stub_advertiser
    stub_campaigns
    stub_ads({ "date_from" => "2026-10-11" }, [ ad.merge(metrics: ad[:metrics].merge(clicks: 1)) ])
    stub_ads({ "date_from" => "2026-09-18" }, [ ad.merge(metrics: ad[:metrics].merge(clicks: 5)) ])
    stub_ads({ "date_from" => "2026-07-20" }, [ ad ])

    # o stub do diário vem por último: o WebMock usa o stub mais recente que combina
    stub_ads({ aggregation_type: "DAILY" }, [
      { date: "2026-10-16", clicks: 4, prints: 400, cost: 2.0, total_amount: 20.0, direct_amount: 15.0, indirect_amount: 5.0,
        units_quantity: 1, direct_units_quantity: 1, indirect_units_quantity: 0, organic_units_quantity: 3, organic_units_amount: 90.0 },
      { date: "2026-10-17", clicks: 6, prints: 600, cost: 3.0, total_amount: 40.0, units_quantity: 1 }
    ])
    result = described_class.call(client, account, today: today)

    expect(result).to have_attributes(campaigns: 1, items: 1, days: 2, ok: true)
    campaign = MlAdCampaign.find_by!(ml_account_id: account.id, campaign_id: 111)
    expect(campaign).to have_attributes(name: "Maquiagens", status: "active", acos_target: 9.09, daily_budget: 110.0)
    expect(MlAdDailyMetric.where(ml_account_id: account.id).sum(:cost)).to eq(5.0)
    item = MlAdItem.find_by!(ml_account_id: account.id, item_id: "MLB1")
    expect(item.title).to eq("Batom")
    expect(item.metrics.keys).to match_array(%w[7d 30d 90d])
    expect(item.metrics["7d"]["clicks"]).to eq(1)
    expect(item.metrics["90d"]["clicks"]).to eq(10)
    expect(account.reload.ads_synced_at).to be_present
  end

  it "anúncio que saiu das campanhas é removido na leitura seguinte" do
    stub_advertiser
    stub_campaigns
    stub_ads({ aggregation_type: "DAILY" }, [])
    stub_ads({}, [ ad ])
    described_class.call(client, account, today: today)

    MlAdItem.create!(ml_account_id: account.id, item_id: "MLB-VELHO", synced_at: 2.days.ago)
    described_class.call(client, account, today: today)

    expect(MlAdItem.where(ml_account_id: account.id).pluck(:item_id)).to eq([ "MLB1" ])
  end

  it "leitura rápida: só ontem e hoje das campanhas já conhecidas" do
    MlAdCampaign.create!(ml_account_id: account.id, campaign_id: 111, name: "Maquiagens", status: "active")
    account.update_columns(ads_advertiser_id: 29_660)
    stub_ads({ aggregation_type: "DAILY", "date_from" => "2026-10-16" }, [
      { date: "2026-10-16", clicks: 4, prints: 400, cost: 2.0, total_amount: 20.0, units_quantity: 1 },
      { date: "2026-10-17", clicks: 6, prints: 600, cost: 3.0, total_amount: 40.0, units_quantity: 1 }
    ])

    result = described_class.refresh_recent(client, account, today: today)

    expect(result).to have_attributes(days: 2, ok: true)
    expect(MlAdDailyMetric.where(ml_account_id: account.id).sum(:cost)).to eq(5.0)
    expect(account.reload.ads_recent_synced_at).to be_present
    expect(WebMock).not_to have_requested(:get, %r{/campaigns/search})
  end

  it "consulta na hora as métricas por anúncio de um período qualquer" do
    account.update_columns(ads_advertiser_id: 29_660)
    stub_ads({ "date_from" => "2026-10-17", "date_to" => "2026-10-17" }, [ ad ])

    metrics = described_class.live_items(client, account, today, today)

    expect(metrics).to eq({ "MLB1" => { "clicks" => 10, "prints" => 1000, "cost" => 5.0, "total_amount" => 60.0, "units_quantity" => 2 } })
  end

  it "conta sem publicidade vira nota, sem erro" do
    stub_request(:get, "https://api.mercadolibre.com/advertising/advertisers").with(query: { product_id: "PADS" })
      .to_return(status: 200, body: { advertisers: [] }.to_json)

    result = described_class.call(client, account, today: today)

    expect(result.ok).to be false
    expect(result.notes.first).to include("Product Ads")
  end

  it "erro do Mercado Livre vira nota" do
    stub_request(:get, "https://api.mercadolibre.com/advertising/advertisers").with(query: { product_id: "PADS" })
      .to_return(status: 403, body: "{}")

    result = described_class.call(client, account, today: today)

    expect(result.ok).to be false
    expect(result.notes.first).to include("publicidade")
  end
end
