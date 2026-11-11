require "rails_helper"

RSpec.describe "Perguntas (/api/questions)", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }

  def question(id, status: "UNANSWERED", item_id: "MLB1", text: "Tem na cor rosa?", answer: nil, at: 1.hour.ago)
    account.ml_questions.create!(question_id: id, item_id: item_id, status: status, text: text, date_created: at, from_id: 99,
                                 answer_text: answer, answer_status: answer && "ACTIVE")
  end

  before do
    create(:ml_item, ml_account: account, item_id: "MLB1", title: "Gloss Labial Letty", price: 30.0)
    allow(Ml::OAuth).to receive(:refresh!)
  end

  it "lista primeiro as sem resposta, com o anúncio, contadores e busca" do
    question(1)
    question(2, status: "ANSWERED", answer: "Temos sim!", at: 2.hours.ago)

    get "/api/questions", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["questions"].map { |q| q["id"] }).to eq([ 1 ])
    expect(json["counts"]).to eq("sem_resposta" => 1, "respondidas" => 1, "todas" => 2)
    expect(json["questions"].first).to include("answerable" => true, "status_label" => "Sem resposta")
    expect(json["questions"].first["item"]).to include("title" => "Gloss Labial Letty")

    get "/api/questions", params: { account_id: account.id, view: "todas", q: "gloss" }, headers: auth_headers(member)
    expect(json["questions"].map { |q| q["id"] }).to eq([ 1, 2 ])
  end

  it "responde no ML só com admin e confirmação, registra e atualiza a pergunta" do
    question(1)
    post_answer = stub_request(:post, "#{ml}/answers").with(body: { question_id: 1, text: "Temos sim, na cor rosa!" }.to_json)
      .to_return(status: 200, body: "{}")
    stub_request(:get, "#{ml}/questions/1?api_version=4").to_return(status: 200, body: {
      id: 1, item_id: "MLB1", status: "ANSWERED", text: "Tem na cor rosa?", answer: { text: "Temos sim, na cor rosa!", status: "ACTIVE" }
    }.to_json)

    post "/api/questions/1/answer", params: { account_id: account.id, text: "Temos sim, na cor rosa!", confirm: true }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)
    post "/api/questions/1/answer", params: { account_id: account.id, text: "Temos sim, na cor rosa!" }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)

    post "/api/questions/1/answer", params: { account_id: account.id, text: "Temos sim, na cor rosa!", confirm: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(post_answer).to have_been_requested.once
    expect(json["question"]).to include("status" => "ANSWERED", "answerable" => false)
    expect(account.ml_question_answers.sole).to have_attributes(ok: true, user_id: admin.id)

    post "/api/questions/1/answer", params: { account_id: account.id, text: "De novo", confirm: true }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "apaga a pergunta no ML (admin, confirmação) e ela sai da lista" do
    question(1)
    del = stub_request(:delete, "#{ml}/questions/1").to_return(status: 200, body: "Question deleted.")

    delete "/api/questions/1", params: { account_id: account.id, confirm: true }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)
    delete "/api/questions/1", params: { account_id: account.id }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)

    delete "/api/questions/1", params: { account_id: account.id, confirm: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(del).to have_been_requested.once
    get "/api/questions", params: { account_id: account.id, view: "todas" }, headers: auth_headers(member)
    expect(json["questions"]).to eq([])
  end

  it "sugere resposta pela IA com as respostas do mesmo anúncio e dos anúncios do mesmo SKU" do
    company.update!(openrouter_api_key: "sk-or")
    account.ml_items.find_by(item_id: "MLB1").update!(sku: "LS-GLOSS-01")
    create(:ml_item, ml_account: account, item_id: "MLB2", title: "Gloss Labial Letty Kit", sku: "LS-GLOSS-01", price: 50.0)
    question(1)
    question(2, item_id: "MLB2", status: "ANSWERED", text: "É vegano?", answer: "Olá! Sim, é vegano. Att Lunna Shop")
    question(3, status: "ANSWERED", text: "Tem cheiro?", answer: "Olá! Tem leve aroma de baunilha. Att Lunna Shop")
    stub_request(:get, "#{ml}/items/MLB1").to_return(status: 200, body: { attributes: [ { name: "Cor", value_name: "Rosa" } ] }.to_json)
    stub_request(:get, "#{ml}/items/MLB1/description").to_return(status: 200, body: { plain_text: "Gloss vegano" }.to_json)
    ai = stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .with { |req| req.body.include?("Sim, é vegano") && req.body.include?("baunilha") && req.body.include?("Cor: Rosa") }
      .to_return(status: 200, body: { choices: [ { message: { content: { answer: "Olá! Temos sim, na cor rosa. Att Lunna Shop", sources: [ "ficha técnica" ], confidence: "alta" }.to_json } } ] }.to_json)

    post "/api/questions/1/suggest", params: { account_id: account.id }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(ai).to have_been_requested
    expect(json).to include("answer" => "Olá! Temos sim, na cor rosa. Att Lunna Shop", "confidence" => "alta")
    expect(json["used"]).to include("same_item" => 1, "same_sku" => 1, "skus" => [ "LS-GLOSS-01" ])
  end

  it "erro do ML vira mensagem e fica registrado" do
    question(1)
    stub_request(:post, "#{ml}/answers").to_return(status: 400, body: { message: "contact info not allowed" }.to_json)

    post "/api/questions/1/answer", params: { account_id: account.id, text: "Chama no zap", confirm: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["errors"].first).to include("recusou")
    expect(account.ml_question_answers.sole).to have_attributes(ok: false)
  end

  it "respostas padrão: incluir, editar e excluir (escrita só admin)" do
    post "/api/question_templates", params: { account_id: account.id, title: "Original", body: "Sim, produto original." }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)

    post "/api/question_templates", params: { account_id: account.id, title: "Original", body: "Sim, produto original." }, headers: auth_headers(admin)
    expect(response).to have_http_status(:created)
    id = json["id"]

    patch "/api/question_templates/#{id}", params: { account_id: account.id, body: "Sim! Produto original com nota fiscal." }, headers: auth_headers(admin)
    expect(json["body"]).to eq("Sim! Produto original com nota fiscal.")

    get "/api/question_templates", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["templates"].map { |t| t["title"] }).to eq([ "Original" ])

    delete "/api/question_templates/#{id}", params: { account_id: account.id }, headers: auth_headers(admin)
    expect(response).to have_http_status(:no_content)
    expect(company.question_templates.count).to eq(0)
  end

  describe Ml::Sync::Questions do
    it "importa as perguntas com a resposta" do
      client = Ml::Client.new(access_token: "tok", sleeper: ->(_) { })
      body = { total: 1, questions: [ { id: 5, item_id: "MLB1", status: "ANSWERED", text: "É original?", date_created: "2026-10-29T16:40:44-04:00",
                                        from: { id: 7 }, answer: { text: "Sim!", status: "ACTIVE", date_created: "2026-10-29T17:02:18-04:00" } } ] }
      stub_request(:get, %r{#{ml}/questions/search}).to_return(status: 200, body: body.to_json)

      described_class.call(client, account)

      expect(account.ml_questions.sole).to have_attributes(question_id: 5, status: "ANSWERED", answer_text: "Sim!", from_id: 7)
      expect(account.reload.questions_synced_at).to be_present
    end
  end
end
