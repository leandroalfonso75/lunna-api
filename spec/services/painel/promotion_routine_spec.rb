require "rails_helper"

RSpec.describe Painel::PromotionRoutine do
  let(:company) { create(:company, tax_pct: 10, fixed_expenses_pct: 5, min_margin_pct: 15) }
  let(:account) { create(:ml_account, company: company, expires_at: 3.hours.from_now) }
  let!(:item) { create(:ml_item, ml_account: account, sku: "SKU-A", price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }
  let!(:other) { create(:ml_item, ml_account: account, sku: "SKU-B", price: 100, ship_cost: 10, fee_now: 10, fee_details: { "percentage_fee" => 10, "fixed_fee" => 0 }) }
  let(:fees) { { "price" => 84, "sale_fee" => 8.4, "percentage_fee" => 10, "fixed_fee" => 0 } }

  before do
    allow(Ml::Sync::Promotions).to receive(:call)
    create(:olist_product, company: company, sku: "SKU-A", cost_price: 40, status: "A", kind: "S")
    create(:olist_product, company: company, sku: "SKU-B", cost_price: 40, status: "A", kind: "S")
    [ item, other ].each do |i|
      MlPromotionOffer.create!(ml_account: account, item_id: i.item_id, promotion_id: "C-1", promotion_type: "SELLER_CAMPAIGN", name: "C-1",
        status: "started", price: 80, original_price: 100, min_price: 50, max_price: 80, fees: fees)
      MlPromotionOffer.create!(ml_account: account, item_id: i.item_id, promotion_id: "P-2", promotion_type: "DEAL", name: "Evento",
        status: "candidate", original_price: 100, min_price: 50, max_price: 95, meli_percentage: 2, fees: fees)
    end
  end

  it "em simulação registra o antes e o depois de cada anúncio e não chama o ML" do
    run = described_class.call(account, mode: "simulation", trigger: "manual")

    expect(run).to have_attributes(status: "done", mode: "simulation")
    expect(run.totals).to include("simulado" => 2, "anuncios" => 2)
    action = run.actions.find_by(item_id: item.item_id)
    expect(action).to have_attributes(source: "simulacao", kind: "trocar", from_price: 80, to_price: 80, ok: true)
    expect(action.to_profit).to be > action.from_profit
    expect(a_request(:any, /seller-promotions/)).not_to have_been_made
  end

  it "não mexe em anúncio com regra própria em texto e registra o motivo" do
    MlPromotionSetting.create!(ml_account: account, item_id: other.item_id, rules_note: "Nunca entrar em evento")

    run = described_class.call(account, mode: "simulation", trigger: "manual")

    expect(run.totals).to include("simulado" => 1, "regra_propria" => 1)
    expect(run.actions.find_by(item_id: other.item_id)).to have_attributes(kind: "pular", error: a_string_including("Nunca entrar em evento"))
  end

  it "em aplicação real usa a mesma ação da tela, ligada à execução" do
    allow(Painel::PromotionActions).to receive(:apply).and_return(Painel::PromotionActions::Result.new(ok: true, message: "ok"))

    run = described_class.call(account, mode: "apply", trigger: "agendada")

    expect(run.totals).to include("aplicado" => 2)
    expect(Painel::PromotionActions).to have_received(:apply).with(account, item.item_id, source: "rotina", run: run)
  end

  it "o job agendado só roda para empresas com a rotina ligada, no modo escolhido" do
    allow(described_class).to receive(:call)
    Ml::PromotionsRoutineJob.perform_now
    expect(described_class).not_to have_received(:call)

    company.update!(promo_routine_enabled: true, promo_routine_mode: "apply")
    Ml::PromotionsRoutineJob.perform_now
    expect(described_class).to have_received(:call).with(account, mode: "apply", trigger: "agendada")
  end

  it "anúncio marcado para não automatizar não é mexido, mas a melhor oferta fica registrada como sugestão" do
    MlPromotionSetting.create!(ml_account: account, item_id: other.item_id, automation_enabled: false)

    run = described_class.call(account, mode: "simulation", trigger: "manual")

    expect(run.totals).to include("simulado" => 1, "automacao_desligada" => 1)
    skipped = run.actions.find_by(item_id: other.item_id)
    expect(skipped).to have_attributes(kind: "pular", error: a_string_including("não automatizar"))
    expect(skipped.to_price).to be_present
  end
end
