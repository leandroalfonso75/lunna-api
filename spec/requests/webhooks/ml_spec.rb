require "rails_helper"

RSpec.describe "POST /webhooks/ml", type: :request do
  it "devolve 200 sem autenticação e sem processar nada" do
    post "/webhooks/ml", params: { topic: "orders_v2", resource: "/orders/123" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
  end
end
