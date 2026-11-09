require "rails_helper"

RSpec.describe "Curva ABC: alterar título, ficha técnica e Ciente", type: :request do
  let(:company) { create(:company, openrouter_api_key: "sk-or", ai_model: "openai/gpt-4o-mini") }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }
  let(:item) do
    { "id" => "MLB1", "title" => "Gloss Labial Vegano Letty Gummy", "family_name" => "Gloss Labial Vegano Letty", "user_product_id" => "MLBU1",
      "sold_quantity" => 0, "catalog_listing" => false, "category_id" => "MLB29888",
      "attributes" => [ { "id" => "BRAND", "name" => "Marca", "value_name" => "Letty" } ] }
  end

  before do
    create(:ml_item, ml_account: account, item_id: "MLB1", price: 30.0)
    allow(Ml::OAuth).to receive(:refresh!)
    stub_request(:get, "#{ml}/items/MLB1").to_return(status: 200, body: item.to_json)
    stub_request(:get, %r{#{ml}/users/430/items/search}).to_return(status: 200, body: { results: [ "MLB1", "MLB2" ] }.to_json)
    stub_request(:get, "#{ml}/items/MLB2").to_return(status: 200, body: { id: "MLB2", sold_quantity: 0 }.to_json)
    stub_request(:get, "#{ml}/categories/MLB29888").to_return(status: 200, body: { settings: { max_title_length: 60 } }.to_json)
  end

  describe "título" do
    it "não deixa trocar quando outro anúncio do mesmo produto já vendeu" do
      stub_request(:get, "#{ml}/items/MLB2").to_return(status: 200, body: { id: "MLB2", sold_quantity: 4 }.to_json)

      get "/api/items/MLB1/title", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json).to include("editable" => false, "mode" => "family_name", "sold" => 4)
      expect(json["reason"]).to include("já tem 4 venda")

      post "/api/items/MLB1/title", params: { account_id: account.id, text: "Gloss Novo", confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "publica o novo nome da família (modelo User Products) só com admin e confirmação, e registra" do
      put = stub_request(:put, "#{ml}/items/MLB1").with(body: { family_name: "Gloss Labial Hidratante Vegano Letty" }.to_json)
        .to_return(status: 200, body: "{}")

      post "/api/items/MLB1/title", params: { account_id: account.id, text: "Gloss Labial Hidratante Vegano Letty", confirm: true }, headers: auth_headers(member)
      expect(response).to have_http_status(:forbidden)
      post "/api/items/MLB1/title", params: { account_id: account.id, text: "Gloss Labial Hidratante Vegano Letty" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      post "/api/items/MLB1/title", params: { account_id: account.id, text: "x" * 61, confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)

      post "/api/items/MLB1/title", params: { account_id: account.id, text: "Gloss Labial Hidratante Vegano Letty", confirm: true }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(put).to have_been_requested.once
      edit = account.ml_item_edits.sole
      expect(edit).to have_attributes(kind: "titulo", ok: true, user_id: admin.id)
      expect(edit.before).to include("title" => "Gloss Labial Vegano Letty Gummy")
    end

    it "sugere 5 títulos pela IA, cortados no limite" do
      long = "Gloss Labial Vegano Hidratante Longa Duração Letty Gummy Brilho Intenso Extra"
      titles = [ { title: long, why: "palavras buscadas" } ] + (1..5).map { |i| { title: "Gloss Labial Vegano Letty #{i}", why: "x" } }
      stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
        .to_return(status: 200, body: { choices: [ { message: { content: { titles: titles }.to_json } } ] }.to_json)
      stub_request(:get, "#{ml}/items/MLB1/description").to_return(status: 200, body: { plain_text: "Gloss vegano" }.to_json)

      post "/api/items/MLB1/title/suggest", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["titles"].size).to eq(5)
      expect(json["titles"].first).to include("trimmed" => true, "length" => 60)
    end
  end

  describe "ficha técnica" do
    before do
      stub_request(:get, "#{ml}/categories/MLB29888/attributes").to_return(status: 200, body: [
        { id: "BRAND", name: "Marca", value_type: "string", tags: { required: true }, relevance: 1 },
        { id: "MAIN_COLOR", name: "Cor principal", value_type: "list", tags: { fixed_values: true }, relevance: 1, values: [ { id: "52049", name: "Rosa" } ] },
        { id: "SELLER_SKU", name: "SKU", value_type: "string", tags: {}, relevance: 1 },
        { id: "OTHER", name: "Outro", value_type: "string", tags: {}, relevance: 2 },
        { id: "ANVISA_PRIOR_NOTIFICATION_COMMUNICATION_DOCUMENT_NUMBER", name: "Número Anvisa", value_type: "string", tags: {}, relevance: 1 },
        { id: "IS_PLUMPING", name: "É engrossador", value_type: "boolean", tags: {}, relevance: 1, values: [ { id: "242085", name: "Sim" }, { id: "242084", name: "Não" } ] }
      ].to_json)
    end

    it "lista só os campos que faltam e publica os preenchidos (admin, confirmação)" do
      get "/api/items/MLB1/specs", params: { account_id: account.id }, headers: auth_headers(member)
      expect(json["fields"].map { |f| f["id"] }).to eq([ "MAIN_COLOR", "IS_PLUMPING" ]) # documento regulatório fica de fora
      expect(json["fields"].first).to include("free_text" => false, "not_applicable" => true)

      put = stub_request(:put, "#{ml}/items/MLB1")
        .with(body: { attributes: [ { id: "MAIN_COLOR", value_id: "52049" }, { id: "IS_PLUMPING", value_id: "-1", value_name: nil } ] }.to_json)
        .to_return(status: 200, body: "{}")
      post "/api/items/MLB1/specs", params: { account_id: account.id, confirm: true,
                                              values: { MAIN_COLOR: { value_id: "52049" }, BRAND: { value_name: "X" }, IS_PLUMPING: { not_applicable: true } } },
                                    headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(put).to have_been_requested.once
      expect(account.ml_item_edits.sole).to have_attributes(kind: "ficha_tecnica", ok: true)
    end

    it "a IA só sugere valores da lista permitida" do
      content = { values: { MAIN_COLOR: { value_id: "999", value_name: "Rosa", why: "título" }, NOPE: { value_name: "x" } } }
      stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
        .to_return(status: 200, body: { choices: [ { message: { content: content.to_json } } ] }.to_json)
      stub_request(:get, "#{ml}/items/MLB1/description").to_return(status: 404, body: "{}")

      post "/api/items/MLB1/specs/suggest", params: { account_id: account.id }, headers: auth_headers(member)

      expect(json["values"]).to eq("MAIN_COLOR" => { "value_id" => "52049", "value_name" => "Rosa", "why" => "título" })
    end
  end

  it "Ciente, aguardar: esconde a sugestão por 15 dias" do
    post "/api/items/MLB1/suggestion_acks", params: { account_id: account.id, key: "vídeo:Adicionar vídeo", kind: "aguardar" }, headers: auth_headers(member)

    expect(response).to have_http_status(:ok)
    expect(json["message"]).to include("15 dias")
    ack = account.abc_suggestion_acks.sole
    expect(ack.until_at).to be_within(1.minute).of(15.days.from_now)

    post "/api/items/MLB1/suggestion_acks", params: { account_id: account.id, key: "x", kind: "outro" }, headers: auth_headers(member)
    expect(response).to have_http_status(:unprocessable_content)
  end

  describe "preço" do
    before { stub_request(:get, "#{ml}/items/MLB1").to_return(status: 200, body: item.merge("price" => 74.9).to_json) }

    it "aplica o novo preço no ML só com admin e confirmação, registra e trava mudanças grandes" do
      put = stub_request(:put, "#{ml}/items/MLB1").with(body: { price: 83.58 }.to_json).to_return(status: 200, body: "{}")

      post "/api/items/MLB1/price", params: { account_id: account.id, price: 83.58, confirm: true }, headers: auth_headers(member)
      expect(response).to have_http_status(:forbidden)
      post "/api/items/MLB1/price", params: { account_id: account.id, price: 83.58 }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      post "/api/items/MLB1/price", params: { account_id: account.id, price: 200, confirm: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("grande demais")

      post "/api/items/MLB1/price", params: { account_id: account.id, price: "83,58", confirm: true }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json["message"]).to include("frete grátis")
      expect(put).to have_been_requested.once
      expect(account.ml_item_edits.sole).to have_attributes(kind: "preco", ok: true)
      expect(account.ml_items.find_by(item_id: "MLB1").price.to_f).to eq(83.58)
      hold = account.abc_suggestion_acks.find_by(item_id: "MLB1", key: AbcSuggestionAck::PRICE_KEY)
      expect(hold).to have_attributes(kind: "aplicada")
      expect(hold.until_at).to be_within(1.minute).of(15.days.from_now) # sugestões de preço em maturação por 15 dias
    end

    it "no mesmo preço, aplicar o cenário com frete grátis liga o frete grátis" do
      put = stub_request(:put, "#{ml}/items/MLB1").with(body: { shipping: { free_shipping: true } }.to_json).to_return(status: 200, body: "{}")

      post "/api/items/MLB1/price", params: { account_id: account.id, price: 74.9, free_shipping: true, confirm: true }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json["message"]).to include("Frete grátis ligado")
      expect(put).to have_been_requested.once
    end
  end

  it "anúncio de outra conta é 404" do
    get "/api/items/MLB999/title", params: { account_id: account.id }, headers: auth_headers(member)
    expect(response).to have_http_status(:not_found)
  end
end
