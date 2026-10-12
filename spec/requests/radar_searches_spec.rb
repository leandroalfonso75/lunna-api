require "rails_helper"

RSpec.describe "/api/radar/searches", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }

  describe "GET /api/radar/searches" do
    it "lista só as consultas da empresa dos últimos 3 meses, da mais nova para a mais antiga" do
      older = create(:radar_search, company: company, created_at: 2.months.ago)
      newer = create(:radar_search, company: company, created_at: 1.day.ago)
      expired = create(:radar_search, company: company, created_at: 4.months.ago)
      other = create(:radar_search)

      get "/api/radar/searches", headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      ids = json["searches"].map { |s| s["id"] }
      expect(ids).to eq([ newer.id, older.id ])
      expect(ids).not_to include(expired.id, other.id)
    end

    it "exige autenticação" do
      get "/api/radar/searches"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/radar/searches/:id" do
    it "devolve a consulta com os filtros salvos" do
      search = create(:radar_search, company: company, filters: { "category" => "Pet Shop", "priceMin" => "100" })

      get "/api/radar/searches/#{search.id}", headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      expect(json["search"]["filters"]).to eq("category" => "Pet Shop", "priceMin" => "100")
    end

    it "consulta de outra empresa é 404" do
      other = create(:radar_search)

      get "/api/radar/searches/#{other.id}", headers: auth_headers(member)

      expect(response).to have_http_status(:not_found)
    end

    it "consulta com mais de 3 meses é 404" do
      old = create(:radar_search, company: company, created_at: 4.months.ago)

      get "/api/radar/searches/#{old.id}", headers: auth_headers(member)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/radar/searches" do
    let(:body) do
      {
        category_path: "Beleza e Cuidado Pessoal > Perfumes",
        filters: { category: "Beleza e Cuidado Pessoal > Perfumes", period: 30, priceMin: "100" },
        data_ref: "2026-09-23", total_items: 120, total_sold: 5000, total_revenue: 250_000.5, median_price: 79.9
      }
    end

    it "salva a consulta com quem pesquisou" do
      post "/api/radar/searches", params: body, headers: auth_headers(member), as: :json

      expect(response).to have_http_status(:created)
      saved = company.radar_searches.last
      expect(saved.user).to eq(member)
      expect(saved.filters).to include("period" => 30, "priceMin" => "100")
      expect(json["search"]).to include("category_path" => "Beleza e Cuidado Pessoal > Perfumes", "total_items" => 120, "searched_by" => member.name)
    end

    it "422 sem categoria" do
      post "/api/radar/searches", params: body.merge(category_path: ""), headers: auth_headers(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 com total negativo" do
      post "/api/radar/searches", params: body.merge(total_items: -1), headers: auth_headers(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 com filtros grandes demais" do
      post "/api/radar/searches", params: body.merge(filters: { x: "a" * 5000 }), headers: auth_headers(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
