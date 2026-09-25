require "rails_helper"

RSpec.describe Painel::SyncStatus do
  let(:account) { create(:ml_account) }

  it "bad: conta reauth_required, mesmo com rodada ok recente" do
    account.update!(status: "reauth_required", last_error: "Falha ao renovar token.")
    create(:ml_sync_run, ml_account: account, ok: true, started_at: 1.minute.ago, finished_at: 1.minute.ago)

    status = described_class.call(account)

    expect(status[:state]).to eq("bad")
    expect(status[:notice]).to eq(title: "Reautorização necessária", body: "Falha ao renovar token.")
  end

  it "bad: nunca houve rodada ok" do
    create(:ml_sync_run, ml_account: account, ok: false, started_at: 5.minutes.ago, finished_at: 5.minutes.ago)

    status = described_class.call(account)

    expect(status[:state]).to eq("bad")
    expect(status[:last_ok_at]).to be_nil
    expect(status[:notice][:title]).to eq("Aguardando a primeira sincronização")
  end

  it "warn: última rodada terminada falhou" do
    create(:ml_sync_run, ml_account: account, ok: true, started_at: 10.minutes.ago, finished_at: 10.minutes.ago)
    create(:ml_sync_run, ml_account: account, ok: false, started_at: 2.minutes.ago, finished_at: 2.minutes.ago, detail: "timeout no ML")

    status = described_class.call(account)

    expect(status[:state]).to eq("warn")
    expect(status[:notice]).to eq(title: "A última sincronização falhou", body: "timeout no ML")
  end

  it "ok: última rodada ok há exatamente 20 minutos" do
    freeze_time
    create(:ml_sync_run, ml_account: account, ok: true, started_at: 20.minutes.ago, finished_at: 20.minutes.ago)

    status = described_class.call(account)

    expect(status[:state]).to eq("ok")
    expect(status[:notice]).to be_nil
  end

  it "warn: última rodada ok há 20 minutos e 1 segundo (atrasada)" do
    create(:ml_sync_run, ml_account: account, ok: true, started_at: (20.minutes + 1.second).ago, finished_at: (20.minutes + 1.second).ago)

    status = described_class.call(account)

    expect(status[:state]).to eq("warn")
    expect(status[:notice][:title]).to eq("Sincronização atrasada")
  end
end
