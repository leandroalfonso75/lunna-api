require "rails_helper"

RSpec.describe "POST /auth/sign_up", type: :request do
  # `rate_limit` usa o cache store do controller (config.action_controller.
  # cache_store), não Rails.cache — precisa ser limpo entre exemplos pra um
  # spec não herdar contagem de outro.
  before { ApplicationController.cache_store.clear }

  let(:params) do
    { company_name: "Loja da Lunna", name: "Ana Admin", email: "ana@example.com", password: "password123" }
  end

  it "cria empresa + usuário admin + sessão e devolve o token" do
    post "/auth/sign_up", params: params

    expect(response).to have_http_status(:created)
    expect(json["token"]).to be_present
    expect(json["user"]["email"]).to eq("ana@example.com")
    expect(json["user"]["role"]).to eq("admin")
    expect(json["company"]["name"]).to eq("Loja da Lunna")
    expect(json["ml_accounts"]).to eq([])

    expect(Company.count).to eq(1)
    expect(User.sole.admin?).to be true
    expect(Session.count).to eq(1)
  end

  it "não expõe password_digest no payload do usuário" do
    post "/auth/sign_up", params: params

    expect(json["user"]).not_to have_key("password_digest")
  end

  it "devolve 422 pra e-mail repetido" do
    create(:user, email: "ana@example.com")

    post "/auth/sign_up", params: params

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["errors"]).to be_present
    expect(Company.count).to eq(1) # não cria empresa órfã
  end

  it "devolve 422 pra senha curta" do
    post "/auth/sign_up", params: params.merge(password: "123")

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "limita tentativas (429) depois de 5 numa hora" do
    5.times do |n|
      post "/auth/sign_up", params: params.merge(email: "user#{n}@example.com")
    end

    post "/auth/sign_up", params: params.merge(email: "outro@example.com")

    expect(response).to have_http_status(:too_many_requests)
    expect(json["errors"]).to eq([ "Muitas tentativas. Tente de novo em instantes." ])
  end
end
