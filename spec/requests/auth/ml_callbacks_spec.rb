require "rails_helper"

RSpec.describe "GET /auth/ml/callback", type: :request do
  before do
    stub_env("FRONT_URL" => "https://app.lunna.test")
  end

  def expect_redirect_to(query)
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to eq("https://app.lunna.test/configuracoes?aba=contas#{query}")
  end

  it "veio error → redireciona com ml=cancelada, sem tocar no banco" do
    get "/auth/ml/callback", params: { error: "access_denied", state: "qualquer" }

    expect_redirect_to("&ml=cancelada")
  end

  it "sem code → ml=link_invalido" do
    get "/auth/ml/callback", params: { state: "abc" }

    expect_redirect_to("&ml=link_invalido")
  end

  it "sem state → ml=link_invalido" do
    get "/auth/ml/callback", params: { code: "abc" }

    expect_redirect_to("&ml=link_invalido")
  end

  it "com code e state → repassa os dois pro front (escapados), sem consultar o banco nem o ML" do
    get "/auth/ml/callback", params: { code: "a b&c", state: "state-xyz" }

    expect_redirect_to("&code=#{CGI.escape("a b&c")}&state=state-xyz")
  end

  it "não grava nem lê MlOauthState nem MlAccount (é puro repasse)" do
    expect(MlOauthState).not_to receive(:transaction)
    expect(MlAccount).not_to receive(:find_or_initialize_by)

    get "/auth/ml/callback", params: { code: "abc", state: "xyz" }

    expect(response).to have_http_status(:found)
  end
end
