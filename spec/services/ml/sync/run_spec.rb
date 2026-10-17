require "rails_helper"

RSpec.describe Ml::Sync::Run do
  let(:account) { create(:ml_account, seller_id: 430_014_725, expires_at: 6.hours.from_now) }
  let(:sleeper) { ->(_) { } }

  # Rede de segurança: qualquer chamada ao ML não estubada explicitamente no
  # teste devolve 404 (tratado sem estourar em todas as etapas) em vez de
  # `WebMock::NetConnectNotAllowedError`. Cada teste sobrescreve por cima só
  # o que importa pro cenário.
  before do
    stub_request(:get, %r{\Ahttps://api\.mercadolibre\.com/}).to_return(status: 404, body: '{"message":"not found"}')
  end

  def stub_empty_scan_and_orders
    stub_request(:get, "https://api.mercadolibre.com/users/430014725/items/search")
      .with(query: hash_including(search_type: "scan"))
      .to_return(status: 200, body: { results: [], scroll_id: "s" }.to_json)
    stub_request(:get, "https://api.mercadolibre.com/orders/search")
      .with(query: hash_including(seller: "430014725"))
      .to_return(status: 200, body: { paging: { total: 0 }, results: [] }.to_json)
  end

  describe "falha de token (etapa 0)" do
    it "encerra a rodada com ok: false e detail = last_error, sem chamar mais nada no ML" do
      account.update!(expires_at: 1.minute.from_now, refresh_token: "TG-old")
      stub_request(:post, "https://api.mercadolibre.com/oauth/token")
        .to_return(status: 400, body: ml_fixture("error_invalid_grant"))

      described_class.call(account, sleeper: sleeper)

      run = MlSyncRun.last
      expect(run.ok).to be false
      expect(run.detail).to eq("Falha ao renovar token do Mercado Livre. Autorize de novo.")
      expect(WebMock).not_to have_requested(:get, "https://api.mercadolibre.com/users/430014725/items/search")
    end
  end

  describe "erro inesperado" do
    it "fecha a rodada como falha na hora e propaga a exceção" do
      stub_empty_scan_and_orders
      allow(Ml::Sync::Items).to receive(:call).and_raise(RuntimeError, "boom")

      expect { described_class.call(account, sleeper: sleeper) }.to raise_error(RuntimeError, "boom")

      run = MlSyncRun.last
      expect(run.finished_at).to be_present
      expect(run.ok).to be false
      expect(run.detail).to include("Erro inesperado na sincronização (RuntimeError).")
    end
  end

  describe "falha parcial" do
    it "visitas com 500 não derruba a rodada: ok: true com nota" do
      create(:ml_item, ml_account: account, item_id: "MLB1", status: "active")
      stub_empty_scan_and_orders
      stub_request(:get, "https://api.mercadolibre.com/items/MLB1/visits/time_window")
        .to_return(status: 500, body: "erro")

      described_class.call(account, sleeper: sleeper)

      run = MlSyncRun.last
      expect(run.ok).to be true
      expect(run.detail).to include("visitas")
    end
  end

  describe "qualidade e anúncios de catálogo" do
    it "não consulta a qualidade de anúncio de catálogo (o ML responde 400 para product items)" do
      create(:ml_item, ml_account: account, item_id: "MLB1", status: "active", catalog_listing: true)
      create(:ml_item, ml_account: account, item_id: "MLB2", status: "active", catalog_listing: false)
      stub_empty_scan_and_orders

      described_class.call(account, sleeper: sleeper)

      expect(WebMock).not_to have_requested(:get, "https://api.mercadolibre.com/item/MLB1/performance")
      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/item/MLB2/performance")
      expect(MlSyncRun.last.detail.to_s).not_to include("Product items")
    end
  end

  describe "regra dos 6 minutos" do
    it "rodada anterior com 5 min 59 s bloqueia: não faz nada" do
      blocking = create(:ml_sync_run, ml_account: account, started_at: 5.minutes.ago - 59.seconds, finished_at: nil)

      described_class.call(account, sleeper: sleeper)

      expect(blocking.reload.finished_at).to be_nil
      expect(MlSyncRun.where(ml_account: account).count).to eq(1)
      expect(WebMock).not_to have_requested(:post, "https://api.mercadolibre.com/oauth/token")
    end

    it "rodada anterior com 6 min vira interrompida e a nova segue" do
      stale = create(:ml_sync_run, ml_account: account, started_at: 6.minutes.ago, finished_at: nil)
      stub_empty_scan_and_orders

      described_class.call(account, sleeper: sleeper)

      stale.reload
      expect(stale.finished_at).to be_present
      expect(stale.ok).to be false
      expect(stale.detail).to eq("interrompida")

      new_run = MlSyncRun.where(ml_account: account).order(:started_at).last
      expect(new_run.id).not_to eq(stale.id)
      expect(new_run.ok).to be true
    end
  end

  describe "detail truncado em 2.000 caracteres" do
    it "junta as notas das etapas e corta em 2.000" do
      stub_empty_scan_and_orders
      allow(Ml::Sync::Visits).to receive(:call).and_return(Ml::Sync::Visits::Result.new(notes: [ "x" * 3000 ]))

      described_class.call(account, sleeper: sleeper)

      expect(MlSyncRun.last.detail.length).to eq(2_000)
    end
  end

  describe "seleção por etapa" do
    it "visitas: pula (nem chama o ML) quando visits_synced_at já é recente (< 30 min)" do
      account.update!(visits_synced_at: 10.minutes.ago)
      create(:ml_item, ml_account: account, item_id: "MLB1", status: "active")
      stub_empty_scan_and_orders

      described_class.call(account, sleeper: sleeper)

      expect(WebMock).not_to have_requested(:get, "https://api.mercadolibre.com/items/MLB1/visits/time_window")
      expect(account.reload.visits_synced_at).to be_within(5.seconds).of(10.minutes.ago)
    end

    it "pedidos: busca 95 dias quando orders_backfilled_at é nulo, e marca o carimbo ao terminar sem erro" do
      account.update!(orders_backfilled_at: nil)
      stub_empty_scan_and_orders

      described_class.call(account, sleeper: sleeper)

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/orders/search")
        .with(query: hash_including("order.date_created.from" => 95.days.ago.beginning_of_day.iso8601))
      expect(account.reload.orders_backfilled_at).to be_present
    end

    it "pedidos: busca só 4 dias quando já fez o backfill de 95 dias" do
      account.update!(orders_backfilled_at: 1.day.ago)
      stub_empty_scan_and_orders

      described_class.call(account, sleeper: sleeper)

      expect(WebMock).to have_requested(:get, "https://api.mercadolibre.com/orders/search")
        .with(query: hash_including("order.date_created.from" => 4.days.ago.beginning_of_day.iso8601))
    end

    it "pedidos: não marca orders_backfilled_at quando a carga de 95 dias teve erro" do
      account.update!(orders_backfilled_at: nil)
      stub_request(:get, "https://api.mercadolibre.com/users/430014725/items/search")
        .with(query: hash_including(search_type: "scan"))
        .to_return(status: 200, body: { results: [], scroll_id: "s" }.to_json)
      stub_request(:get, "https://api.mercadolibre.com/orders/search")
        .with(query: hash_including(seller: "430014725"))
        .to_return(status: 500, body: "erro")

      described_class.call(account, sleeper: sleeper)

      expect(account.reload.orders_backfilled_at).to be_nil
      run = MlSyncRun.last
      expect(run.ok).to be true
      expect(run.detail).to include("pedidos")
    end
  end
end
