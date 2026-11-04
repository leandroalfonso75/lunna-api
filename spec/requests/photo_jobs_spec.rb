require "rails_helper"

RSpec.describe "Curva ABC > Fotos", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company, :with_ai) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }
  let(:account) { create(:ml_account, company: company) }
  let(:png) { "\x89PNG\r\n\x1A\nfake".b }
  let(:pictures) { [ { id: "111-MLB", secure_url: "https://http2.mlstatic.com/D_111.jpg" } ] }

  before do
    stub_request(:get, %r{\Ahttps://api\.mercadolibre\.com/items/MLB1\?})
      .to_return(status: 200, body: { id: "MLB1", pictures: pictures }.to_json)
  end

  it "lista as fotos do anúncio e cria o pedido (só admin), gerando pela OpenRouter com as fotos de referência" do
    get "/api/items/MLB1/photos", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["pictures"]).to eq([ { "id" => "111-MLB", "url" => "https://http2.mlstatic.com/D_111.jpg" } ])
    expect(json["ai_configured"]).to be(true)

    body = { account_id: account.id, count: 2, instructions: "fundo branco", reference_urls: [ "https://http2.mlstatic.com/D_111.jpg" ],
             uploads: [ "data:image/png;base64,#{Base64.strict_encode64(png)}" ] }
    post "/api/items/MLB1/photos", params: body, headers: auth_headers(member), as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/items/MLB1/photos", params: body, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    job = MlPhotoJob.last
    expect(job.uploaded_references.size).to eq(1)

    openrouter = stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .with { |req| JSON.parse(req.body).then { |b| b["modalities"] == %w[image text] && b["messages"][0]["content"].size == 3 } }
      .to_return(status: 200, body: { choices: [ { message: { images: [ { image_url: { url: "data:image/png;base64,#{Base64.strict_encode64(png)}" } } ] } } ] }.to_json)
    perform_enqueued_jobs

    expect(openrouter).to have_been_requested.twice
    expect(job.reload).to have_attributes(status: "pronto", error: nil)
    expect(job.generated.size).to eq(2)

    get "/api/photo_images/#{job.generated.first.id}", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response.body.b).to eq(png)
    expect(response.media_type).to eq("image/png")
  end

  it "sem chave da OpenRouter o pedido fica com erro explicando o que fazer" do
    company.update!(openrouter_api_key: nil)
    post "/api/items/MLB1/photos", params: { account_id: account.id, count: 1, reference_urls: [ "https://x/1.jpg" ] },
                                   headers: auth_headers(admin), as: :json
    perform_enqueued_jobs
    expect(MlPhotoJob.last).to have_attributes(status: "erro", error: a_string_including("Configurações › Empresa"))
  end

  it "publica no ML só as aprovadas, com confirmação, mantendo as fotos que já estavam" do
    job = account.ml_photo_jobs.create!(item_id: "MLB1", count: 2, status: "pronto")
    ok = job.photos.create!(kind: "gerada", position: 0, mime: "image/png", data: png)
    job.photos.create!(kind: "gerada", position: 1, mime: "image/png", data: png)

    patch "/api/photo_images/#{ok.id}", params: { account_id: account.id, approved: true }, headers: auth_headers(admin), as: :json
    expect(ok.reload.approved).to be(true)

    post "/api/photo_jobs/#{job.id}/publish", params: { account_id: account.id }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)

    upload = stub_request(:post, "https://api.mercadolibre.com/pictures/items/upload")
      .with(headers: { "Content-Type" => %r{multipart/form-data; boundary=} })
      .to_return(status: 201, body: { id: "999-MLB" }.to_json)
    put = stub_request(:put, "https://api.mercadolibre.com/items/MLB1")
      .with(body: { pictures: [ { id: "111-MLB" }, { id: "999-MLB" } ] }.to_json)
      .to_return(status: 200, body: "{}")

    post "/api/photo_jobs/#{job.id}/publish", params: { account_id: account.id, confirm: true }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(upload).to have_been_requested.once
    expect(put).to have_been_requested.once
    expect(json["published"]).to eq(1)
    expect(job.reload).to have_attributes(status: "publicado")
    expect(ok.reload.ml_picture_id).to eq("999-MLB")
  end
end
