require "rails_helper"

RSpec.describe "sessão (sign_in/sign_out)", type: :request do
  # `rate_limit` usa o cache store do controller (config.action_controller.
  # cache_store), não Rails.cache — precisa ser limpo entre exemplos pra um
  # spec não herdar contagem de outro.
  before { ApplicationController.cache_store.clear }

  describe "POST /auth/sign_in" do
    let!(:user) { create(:user, email: "ana@example.com", password: "password123") }

    it "autentica com credenciais corretas" do
      post "/auth/sign_in", params: { email: "ana@example.com", password: "password123" }

      expect(response).to have_http_status(:ok)
      expect(json["token"]).to be_present
      expect(json["user"]["email"]).to eq("ana@example.com")
      expect(json["company"]["id"]).to eq(user.company_id)
      expect(json["ml_accounts"]).to eq([])
    end

    it "aceita e-mail em outra caixa/com espaços (normalizado)" do
      post "/auth/sign_in", params: { email: "  ANA@Example.com  ", password: "password123" }

      expect(response).to have_http_status(:ok)
    end

    it "devolve 401 pra senha errada" do
      post "/auth/sign_in", params: { email: "ana@example.com", password: "senha-errada" }

      expect(response).to have_http_status(:unauthorized)
      expect(json["errors"]).to eq([ "E-mail ou senha inválidos." ])
    end

    it "devolve 401 pra e-mail inexistente" do
      post "/auth/sign_in", params: { email: "ninguem@example.com", password: "password123" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "limita tentativas (429) depois de 10 em 3 minutos" do
      10.times { post "/auth/sign_in", params: { email: "ana@example.com", password: "senha-errada" } }

      post "/auth/sign_in", params: { email: "ana@example.com", password: "senha-errada" }

      expect(response).to have_http_status(:too_many_requests)
      expect(json["errors"]).to eq([ "Muitas tentativas. Tente de novo em instantes." ])
    end
  end

  describe "DELETE /auth/sign_out" do
    let(:user) { create(:user) }

    it "apaga a sessão atual e devolve 204" do
      headers = auth_headers(user)

      delete "/auth/sign_out", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(Session.count).to eq(0)
    end

    it "o token deixa de valer depois do sign_out" do
      headers = auth_headers(user)
      delete "/auth/sign_out", headers: headers

      get "/api/me", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "devolve 401 sem token" do
      delete "/auth/sign_out"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "token expirado" do
    it "devolve 401" do
      user = create(:user)
      headers = auth_headers(user)
      Session.last.update!(expires_at: 1.second.ago)

      get "/api/me", headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(json["errors"]).to eq([ "não autenticado" ])
    end
  end
end
