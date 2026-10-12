require "rails_helper"

RSpec.describe "Olist sync jobs" do
  let(:company) { create(:company) }
  let(:connection) { create(:olist_connection, company: company) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }

  before do
    ActiveJob::Base.queue_adapter = :test
    stub_request(:get, "#{base}/produtos").with(query: hash_including({}))
      .to_return(status: 200, body: { itens: [ { "id" => 1, "sku" => "A", "descricao" => "A", "precos" => {} } ], paginacao: { total: 1 } }.to_json)
    stub_request(:get, "#{base}/estoque").with(query: hash_including({})).to_return(status: 200, body: { itens: [], paginacao: { total: 0 } }.to_json)
  end

  describe Olist::SyncJob do
    it "automático: cria a rodada e sincroniza" do
      described_class.perform_now(connection.id)

      expect(OlistSyncRun.last).to have_attributes(trigger: "auto", status: "success", products_count: 1)
      expect(OlistProduct.count).to eq(1)
    end

    it "manual: usa a rodada já criada" do
      run, = Olist::SyncProducts.start_run(connection, trigger: "manual")

      described_class.perform_now(connection.id, run.id)

      expect(run.reload.status).to eq("success")
      expect(OlistSyncRun.count).to eq(1)
    end

    it "não faz nada se a conexão precisa ser refeita" do
      connection.update!(status: "reauth_required")

      described_class.perform_now(connection.id)

      expect(OlistSyncRun.count).to eq(0)
    end

    it "não duplica quando já há uma rodada em andamento" do
      create(:olist_sync_run, company: company, started_at: 1.minute.ago)

      described_class.perform_now(connection.id)

      expect(OlistSyncRun.count).to eq(1)
      expect(OlistProduct.count).to eq(0)
    end
  end

  describe Olist::SyncAllJob do
    it "enfileira uma sincronização por conexão ativa" do
      connection
      create(:olist_connection, status: "reauth_required")

      expect { described_class.perform_now }.to have_enqueued_job(Olist::SyncJob).with(connection.id).exactly(:once)
    end
  end

  it "o agendamento roda a cada 3 minutos" do
    config = YAML.safe_load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    expect(config.dig("production", "olist_sync")).to include("class" => "Olist::SyncAllJob", "schedule" => "every 3 minutes")
  end
end
