require "rails_helper"

RSpec.describe "/api/radar/collections", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }

  describe "GET /api/radar/collections" do
    it "lista só os pedidos da própria empresa, do mais novo para o mais antigo" do
      older = create(:radar_collection, company: company, created_at: 2.days.ago)
      newer = create(:radar_collection, company: company, created_at: 1.day.ago)
      other = create(:radar_collection)

      get "/api/radar/collections", headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      ids = json["collections"].map { |c| c["id"] }
      expect(ids).to eq([ newer.id, older.id ])
      expect(ids).not_to include(other.id)
    end

    it "exige autenticação" do
      get "/api/radar/collections"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/radar/collections" do
    it "registra o pedido como requested, sem iniciar nenhuma coleta" do
      post "/api/radar/collections", params: { category_path: "Pet Shop > Cães > Rações" }, headers: auth_headers(member)

      expect(response).to have_http_status(:created)
      expect(json["collection"]).to include("category_path" => "Pet Shop > Cães > Rações", "status" => "requested", "requested_by" => member.name)
      expect(company.radar_collections.count).to eq(1)
    end

    it "normaliza espaços do caminho" do
      post "/api/radar/collections", params: { category_path: "  Pet Shop  >  Cães " }, headers: auth_headers(member)

      expect(json["collection"]["category_path"]).to eq("Pet Shop > Cães")
    end

    it "recusa pedido repetido enquanto o anterior estiver em aberto" do
      create(:radar_collection, company: company, category_path: "Pet Shop", status: "collecting")

      post "/api/radar/collections", params: { category_path: "Pet Shop" }, headers: auth_headers(member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("em aberto")
    end

    it "aceita novo pedido depois que o anterior terminou" do
      create(:radar_collection, company: company, category_path: "Pet Shop", status: "done")

      post "/api/radar/collections", params: { category_path: "Pet Shop" }, headers: auth_headers(member)

      expect(response).to have_http_status(:created)
    end

    it "empresas diferentes podem pedir a mesma categoria" do
      create(:radar_collection, category_path: "Pet Shop")

      post "/api/radar/collections", params: { category_path: "Pet Shop" }, headers: auth_headers(member)

      expect(response).to have_http_status(:created)
    end

    it "422 sem categoria" do
      post "/api/radar/collections", params: { category_path: "" }, headers: auth_headers(member)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/radar/collections/:id" do
    it "cancela um pedido que ainda não começou" do
      collection = create(:radar_collection, company: company)

      delete "/api/radar/collections/#{collection.id}", headers: auth_headers(member)

      expect(response).to have_http_status(:no_content)
      expect(RadarCollection.exists?(collection.id)).to be(false)
    end

    it "não cancela o que já está coletando" do
      collection = create(:radar_collection, company: company, status: "collecting")

      delete "/api/radar/collections/#{collection.id}", headers: auth_headers(member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(RadarCollection.exists?(collection.id)).to be(true)
    end

    it "pedido de outra empresa é 404" do
      other = create(:radar_collection)

      delete "/api/radar/collections/#{other.id}", headers: auth_headers(member)

      expect(response).to have_http_status(:not_found)
    end
  end
end
