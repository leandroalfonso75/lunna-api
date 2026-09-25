require "rails_helper"

RSpec.describe "/api/sync", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }

  describe "POST /api/sync" do
    it "member não pode (403)" do
      post "/api/sync", params: { account_id: account.id }, headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end

    it "conta de outra empresa devolve 404" do
      other_account = create(:ml_account)

      post "/api/sync", params: { account_id: other_account.id }, headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end

    it "admin dispara: 202 com run_id e job enfileirado" do
      expect {
        post "/api/sync", params: { account_id: account.id }, headers: auth_headers(admin)
      }.to have_enqueued_job(Ml::SyncJob)

      expect(response).to have_http_status(:accepted)
      expect(json["run_id"]).to be_present
      expect(MlSyncRun.find(json["run_id"]).ml_account_id).to eq(account.id)
    end

    it "409 quando já existe uma rodada em andamento (< 6 min)" do
      create(:ml_sync_run, ml_account: account, started_at: 1.minute.ago, finished_at: nil)

      post "/api/sync", params: { account_id: account.id }, headers: auth_headers(admin)

      expect(response).to have_http_status(:conflict)
      expect(json["errors"]).to eq([ "Já existe uma sincronização em andamento para esta conta." ])
    end

    it "uma rodada presa há mais de 6 min não bloqueia um novo disparo" do
      create(:ml_sync_run, ml_account: account, started_at: 7.minutes.ago, finished_at: nil)

      post "/api/sync", params: { account_id: account.id }, headers: auth_headers(admin)

      expect(response).to have_http_status(:accepted)
    end
  end

  describe "GET /api/sync/runs" do
    it "só devolve rodadas da própria empresa, mais recentes primeiro" do
      run1 = create(:ml_sync_run, ml_account: account, started_at: 2.hours.ago, finished_at: 2.hours.ago, ok: true, items: 10, orders: 2, detail: "ok")
      run2 = create(:ml_sync_run, ml_account: account, started_at: 1.hour.ago, finished_at: 1.hour.ago, ok: true)
      create(:ml_sync_run) # outra empresa

      get "/api/sync/runs", params: { account_id: account.id }, headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      expect(json["runs"].map { |r| r["id"] }).to eq([ run2.id, run1.id ])
      expect(json["runs"].last).to include("items" => 10, "orders" => 2, "detail" => "ok")
    end

    it "conta de outra empresa devolve 404" do
      other_account = create(:ml_account)

      get "/api/sync/runs", params: { account_id: other_account.id }, headers: auth_headers(member)

      expect(response).to have_http_status(:not_found)
    end

    it "respeita o limit, com teto de 100" do
      create_list(:ml_sync_run, 3, ml_account: account)

      get "/api/sync/runs", params: { account_id: account.id, limit: 2 }, headers: auth_headers(member)

      expect(json["runs"].size).to eq(2)
    end

    it "limit acima de 100 é limitado a 100" do
      get "/api/sync/runs", params: { account_id: account.id, limit: 500 }, headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
    end
  end
end
