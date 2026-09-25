require "rails_helper"

RSpec.describe "/api/users", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }

  describe "GET /api/users" do
    it "admin lista só os usuários da própria empresa" do
      member
      other_company_user = create(:user, :admin)

      get "/api/users", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      ids = json["users"].map { |u| u["id"] }
      expect(ids).to contain_exactly(admin.id, member.id)
      expect(ids).not_to include(other_company_user.id)
    end

    it "member não pode (403)" do
      get "/api/users", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/users" do
    it "admin cria usuário na própria empresa" do
      post "/api/users",
        params: { name: "Novo Membro", email: "novo@example.com", password: "password123", role: "member" },
        headers: auth_headers(admin)

      expect(response).to have_http_status(:created)
      expect(json["user"]["email"]).to eq("novo@example.com")
      expect(company.users.count).to eq(2) # admin + novo
    end

    it "devolve 422 pra e-mail repetido" do
      create(:user, email: "dup@example.com")

      post "/api/users",
        params: { name: "X", email: "dup@example.com", password: "password123", role: "member" },
        headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/users/:id" do
    it "admin atualiza nome/role de outro usuário" do
      patch "/api/users/#{member.id}", params: { name: "Renomeado", role: "admin" }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json["user"]["name"]).to eq("Renomeado")
      expect(json["user"]["role"]).to eq("admin")
    end

    it "devolve 404 pra usuário de outra empresa" do
      outsider = create(:user)

      patch "/api/users/#{outsider.id}", params: { name: "Hackeado" }, headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end

    it "não permite rebaixar o último admin" do
      patch "/api/users/#{admin.id}", params: { role: "member" }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to eq([ "A empresa precisa de pelo menos um administrador." ])
      expect(admin.reload).to be_admin
    end

    it "permite rebaixar um admin quando há outro" do
      other_admin = create(:user, :admin, company: company)

      patch "/api/users/#{admin.id}", params: { role: "member" }, headers: auth_headers(other_admin)

      expect(response).to have_http_status(:ok)
      expect(admin.reload).not_to be_admin
    end

    it "trocar a senha derruba as outras sessões do usuário" do
      other_session_headers = auth_headers(member)
      current_headers = auth_headers(admin)

      patch "/api/users/#{member.id}", params: { password: "novaSenha123" }, headers: current_headers

      expect(response).to have_http_status(:ok)
      get "/api/me", headers: other_session_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/users/:id" do
    it "admin remove outro usuário e apaga as sessões dele" do
      member_headers = auth_headers(member)

      delete "/api/users/#{member.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:no_content)
      expect(company.users.exists?(member.id)).to be false

      get "/api/me", headers: member_headers
      expect(response).to have_http_status(:unauthorized)
    end

    it "não permite remover a si mesmo" do
      delete "/api/users/#{admin.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to eq([ "Você não pode remover o próprio usuário." ])
    end

    it "permite remover um admin quando há outro, mantendo o restante" do
      other_admin = create(:user, :admin, company: company)

      delete "/api/users/#{other_admin.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:no_content)
      expect(company.users.where(role: "admin").count).to eq(1)
    end

    it "devolve 404 pra usuário de outra empresa" do
      outsider = create(:user)

      delete "/api/users/#{outsider.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end
  end
end
