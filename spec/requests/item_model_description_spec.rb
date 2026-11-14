require "rails_helper"

RSpec.describe "Curva ABC: Modelo com palavras-chave e descrição mais chamativa (14/11/2026)", type: :request do
  let(:company) { create(:company, openrouter_api_key: "sk-or", ai_model: "openai/gpt-4o-mini") }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }
  let(:ai) { "https://openrouter.ai/api/v1/chat/completions" }
  let(:variations) { [] }
  let(:item) do
    { "id" => "MLB1", "title" => "Secador De Cabelo Mondial 2000w", "catalog_listing" => false, "category_id" => "MLB1234",
      "attributes" => [ { "id" => "BRAND", "name" => "Marca", "value_name" => "Mondial" }, { "id" => "MODEL", "name" => "Modelo", "value_name" => "SC13" } ],
      "variations" => variations }
  end

  before do
    create(:ml_item, ml_account: account, item_id: "MLB1", price: 99.0, model: "SC13")
    allow(Ml::OAuth).to receive(:refresh!)
    stub_request(:get, "#{ml}/items/MLB1").to_return(status: 200, body: item.to_json)
    stub_request(:get, "#{ml}/categories/MLB1234/attributes").to_return(status: 200, body: [
      { id: "MODEL", name: "Modelo", value_type: "string", value_max_length: 110 },
      { id: "DETAILED_MODEL", name: "Modelo detalhado", value_type: "string", tags: { variation_attribute: true } } ].to_json)
    stub_request(:get, "#{ml}/trends/MLB/MLB1234").to_return(status: 200, body: [ { keyword: "secador profissional" }, { keyword: "secador com difusor" } ].to_json)
    stub_request(:get, "#{ml}/items/MLB1/description").to_return(status: 200, body: { plain_text: "Secador potente." }.to_json)
  end

  def ai_reply(content)
    stub_request(:post, ai).to_return(status: 200, body: { choices: [ { message: { content: content.to_json } } ] }.to_json)
  end

  describe "Modelo" do
    it "mostra o Modelo atual, o limite de 110 e as buscas da categoria; a IA sugere 3 opções cortadas sem quebrar palavra" do
      get "/api/items/MLB1/model", params: { account_id: account.id }, headers: auth_headers(member)
      expect(json).to include("model" => "SC13", "max_length" => 110, "editable" => true, "detailed_per_variation" => false,
                              "trends" => [ "secador profissional", "secador com difusor" ])

      # buscas da categoria (stub): "secador profissional", "secador com difusor"; a IA escolhe e marca outras marcas
      stub_request(:get, "#{ml}/trends/MLB/MLB1234").to_return(status: 200, body: %w[secador\ gama secador\ taiff secador\ de\ cabelo\ com\ difusor
        secador\ mondial secador\ de\ cabelo\ bivolt secador\ de\ cabelos dyson\ airwrap].map { |k| { keyword: k } }.to_json)
      ai_reply(keywords: [ { keyword: "Secador Taiff", other_brand: true }, { keyword: "secador de cabelo com difusor", other_brand: false },
                           { keyword: "secador mondial", other_brand: true }, { keyword: "secador gama", other_brand: true },
                           { keyword: "secador de cabelo bivolt", other_brand: false }, { keyword: "secador inventado", other_brand: false },
                           { keyword: "secador de cabelos", other_brand: false } ],
               detailed_model: "SC13 2000W Íon com Difusor")
      post "/api/items/MLB1/model/suggest", params: { account_id: account.id }, headers: auth_headers(member)

      models = json["options"].map { |o| o["model"] }
      # termos exatos das buscas; as duas primeiras sem outra marca (Mondial é a marca do anúncio); termo inventado fica de fora
      expect(models[0]).to eq("secador de cabelo com difusor secador mondial secador taiff secador gama secador de cabelo bivolt")
      expect(models[0].length).to be <= 110
      expect(models[1]).to start_with("secador de cabelo com difusor secador mondial secador gama secador taiff")
      expect(models[2]).to eq("secador de cabelo com difusor secador mondial secador de cabelo bivolt secador de cabelos")
      expect(models.join).not_to include("inventado", "dyson")
      expect(json["detailed_model"]).to eq("SC13 2000W Íon com Difusor")
    end

    it "publica MODEL e DETAILED_MODEL no anúncio (sem variações), só com admin e confirmação, e registra" do
      put = stub_request(:put, "#{ml}/items/MLB1").with(body: { attributes: [ { id: "MODEL", value_name: "secador profissional com difusor salao" },
                                                                                 { id: "DETAILED_MODEL", value_name: "SC13" } ] }.to_json)
        .to_return(status: 200, body: "{}")
      params = { account_id: account.id, model: "secador profissional com difusor salao", detailed_model: "SC13" }

      post "/api/items/MLB1/model", params: params.merge(confirm: true), headers: auth_headers(member)
      expect(response).to have_http_status(:forbidden)
      post "/api/items/MLB1/model", params: params, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      post "/api/items/MLB1/model", params: params.merge(model: "x" * 111, confirm: true), headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)

      post "/api/items/MLB1/model", params: params.merge(confirm: true), headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(put).to have_been_requested.once
      expect(account.ml_item_edits.sole).to have_attributes(kind: "modelo", ok: true)
      expect(account.ml_items.find_by(item_id: "MLB1").model).to eq("secador profissional com difusor salao")
    end

    context "com variações" do
      let(:variations) { [ { "id" => 11, "attributes" => [ { "id" => "GTIN", "value_name" => "789" } ] }, { "id" => 12, "attributes" => [] } ] }

      it "Modelo detalhado vai em cada variação (mantendo os atributos que ela já tinha)" do
        put = stub_request(:put, "#{ml}/items/MLB1").with(body: {
          attributes: [ { id: "MODEL", value_name: "secador profissional" } ],
          variations: [ { id: 11, attributes: [ { id: "GTIN", value_name: "789" }, { id: "DETAILED_MODEL", value_name: "SC13" } ] },
                        { id: 12, attributes: [ { id: "DETAILED_MODEL", value_name: "SC13" } ] } ] }.to_json).to_return(status: 200, body: "{}")

        post "/api/items/MLB1/model", params: { account_id: account.id, model: "secador profissional", detailed_model: "SC13", confirm: true }, headers: auth_headers(admin)
        expect(response).to have_http_status(:ok)
        expect(put).to have_been_requested.once
      end
    end
  end

  describe "descrição" do
    it "a IA sugere uma descrição em texto puro (sem HTML nem emoji), com as perguntas dos compradores" do
      MlQuestion.create!(ml_account: account, question_id: 1, item_id: "MLB1", text: "Serve para cabelo cacheado?", date_created: 1.day.ago)
      ai = ai_reply(text: "<b>SECADOR POTENTE</b> 🔥\n\n\n\n- Seca rápido", highlights: [ "abertura com benefício" ])

      post "/api/items/MLB1/description/suggest", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["text"]).to eq("SECADOR POTENTE \n\n- Seca rápido".sub(" \n", "\n"))
      expect(ai.with { |req| req.body.include?("cabelo cacheado") }).to have_been_requested
    end

    it "publica a descrição (admin + confirmação), registra e marca a sugestão como aplicada; recusa contato e texto curto" do
      text = ("Descrição nova " * 10).strip
      put = stub_request(:put, "#{ml}/items/MLB1/description").with(query: { api_version: "2" }, body: { plain_text: text }.to_json)
        .to_return(status: 200, body: "{}")

      post "/api/items/MLB1/description", params: { account_id: account.id, text: "curta", confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      post "/api/items/MLB1/description", params: { account_id: account.id, text: "#{text} chame no (11) 98765-4321", confirm: true }, headers: auth_headers(admin)
      expect(json["errors"].first).to include("telefone")

      post "/api/items/MLB1/description", params: { account_id: account.id, text: text, confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(put).to have_been_requested.once
      expect(account.ml_item_edits.sole).to have_attributes(kind: "descricao", ok: true)
      expect(account.abc_suggestion_acks.sole).to have_attributes(key: "descrição:Deixar a descrição mais chamativa", kind: "aplicada")
    end
  end
end
