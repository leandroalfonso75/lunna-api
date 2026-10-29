require "rails_helper"

RSpec.describe Painel::CatalogCheck do
  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 5, min_margin_pct: 15) }
  let(:account) { create(:ml_account, company: company, expires_at: 3.hours.from_now) }
  let!(:item) { create(:ml_item, ml_account: account, sku: "SKU-A", price: 100, catalog_listing: true) }
  let(:action) do
    account.ml_promotion_actions.create!(item_id: item.item_id, kind: "trocar", source: "rotina", ok: true,
      from_promotion_id: "C-1", from_type: "SELLER_CAMPAIGN", from_price: 80, to_promotion_id: "P-2", to_type: "DEAL", to_price: 78)
  end
  let(:ptw) { "https://api.mercadolibre.com/items/#{item.item_id}/price_to_win?siteId=MLB&version=v2" }

  it "agenda a conferência para uma hora depois" do
    expect { described_class.schedule(account, item, action) }.to have_enqueued_job(Ml::CatalogCheckJob)
    expect(account.ml_catalog_checks.last).to have_attributes(status: "aguardando", item_id: item.item_id)
  end

  it "ganhando: só registra" do
    check = described_class.schedule(account, item, action)
    stub_request(:get, ptw).to_return(status: 200, body: { status: "winning" }.to_json)

    expect(described_class.call(check)).to have_attributes(status: "ganhando", ml_status: "winning")
  end

  it "sem ganhar: volta ao preço anterior e confere de novo; sem ganhar ainda, vai para análise manual" do
    check = described_class.schedule(account, item, action)
    stub_request(:get, ptw).to_return(status: 200, body: { status: "competing" }.to_json)
    allow(Painel::PromotionActions).to receive(:apply).and_return(Painel::PromotionActions::Result.new(ok: true, message: "ok"))

    expect { described_class.call(check) }.to have_enqueued_job(Ml::CatalogCheckJob)
    expect(check.reload).to have_attributes(status: "revertido")
    expect(Painel::PromotionActions).to have_received(:apply).with(account, item.item_id, source: "catalogo",
      target: { promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN", price: 80.0, force: true })

    described_class.call(check)
    expect(check.reload).to have_attributes(status: "analise_manual", attempts: 2)
    expect(Painel::PromotionsQuery.call(account, ActionController::Parameters.new({}))[:catalog_alerts].first).to include(item_id: item.item_id)
  end
end
