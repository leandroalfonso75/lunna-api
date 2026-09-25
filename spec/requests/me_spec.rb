require "rails_helper"

RSpec.describe "GET /api/me", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }

  it "devolve 401 sem token" do
    get "/api/me"

    expect(response).to have_http_status(:unauthorized)
    expect(json["errors"]).to eq([ "não autenticado" ])
  end

  it "devolve user, company e ml_accounts da empresa" do
    create(:ml_account, company: company, seller_id: 111)
    create(:ml_account, company: company, seller_id: 222)

    get "/api/me", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json["user"]["id"]).to eq(user.id)
    expect(json["company"]["id"]).to eq(company.id)
    expect(json["ml_accounts"].size).to eq(2)
  end

  it "nunca expõe access_token/refresh_token das ml_accounts" do
    create(:ml_account, company: company, access_token: "segredo-acesso", refresh_token: "segredo-refresh")

    get "/api/me", headers: auth_headers(user)

    body = response.body
    expect(body).not_to include("segredo-acesso")
    expect(body).not_to include("segredo-refresh")
    expect(json["ml_accounts"].first).not_to have_key("access_token")
    expect(json["ml_accounts"].first).not_to have_key("refresh_token")
  end
end
