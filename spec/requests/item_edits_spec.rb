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

    it "anúncio com variações: não pede o que já está nas variações e manda atributo de variação em cada variação" do
      create(:ml_item, ml_account: account, item_id: "MLV", price: 197.0)
      stub_request(:get, "#{ml}/categories/MLB5412/attributes").to_return(status: 200, body: [
        { id: "COLOR", name: "Cor", value_type: "string", tags: { allow_variations: true }, relevance: 1 },
        { id: "VOLTAGE", name: "Voltagem", value_type: "string", tags: { allow_variations: true }, relevance: 1 },
        { id: "TECHNOLOGIES", name: "Tecnologias", value_type: "string", tags: { multivalued: true }, relevance: 1 },
        { id: "MAIN_COLOR", name: "Cor principal", value_type: "list", tags: { variation_attribute: true }, relevance: 1, values: [ { id: "2450295", name: "Preto" } ] },
        { id: "GTIN", name: "Código universal de produto", value_type: "string", tags: { variation_attribute: true, multivalued: true }, relevance: 1 }
      ].to_json)
      stub_request(:get, "#{ml}/items/MLV").to_return(status: 200, body: {
        id: "MLV", title: "Secador", category_id: "MLB5412", attributes: [],
        variations: [
          { id: 11, attribute_combinations: [ { id: "COLOR", value_name: "Preto" }, { id: "VOLTAGE", value_name: "127V" } ], attributes: [ { id: "SELLER_SKU", value_name: "S-127" } ] },
          { id: 12, attribute_combinations: [ { id: "COLOR", value_name: "Preto" }, { id: "VOLTAGE", value_name: "220V" } ], attributes: [] }
        ]
      }.to_json)

      get "/api/items/MLV/specs", params: { account_id: account.id }, headers: auth_headers(member)
      expect(json["fields"].map { |f| [ f["id"], f["per_variation"] ] }).to eq([ [ "TECHNOLOGIES", nil ], [ "MAIN_COLOR", "same" ], [ "GTIN", "each" ] ])
      expect(json["variations"]).to eq([ { "id" => 11, "label" => "Preto · 127V" }, { "id" => 12, "label" => "Preto · 220V" } ])

      put = stub_request(:put, "#{ml}/items/MLV").with(body: {
        attributes: [ { id: "TECHNOLOGIES", value_name: "Ionic" } ],
        variations: [
          { id: 11, attributes: [ { id: "SELLER_SKU", value_name: "S-127" }, { id: "MAIN_COLOR", value_id: "2450295" }, { id: "GTIN", value_name: "7891" } ] },
          { id: 12, attributes: [ { id: "MAIN_COLOR", value_id: "2450295" }, { id: "GTIN", value_name: "7892" } ] }
        ]
      }.to_json).to_return(status: 200, body: "{}")
      post "/api/items/MLV/specs", params: { account_id: account.id, confirm: true,
                                             values: { TECHNOLOGIES: { value_name: "Ionic" }, MAIN_COLOR: { value_id: "2450295" },
                                                       GTIN: { variations: { "11" => { value_name: "7891" }, "12" => { value_name: "7892" } } } } },
                                   headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
      expect(put).to have_been_requested.once
    end

    it "recusa do ML aparece com o motivo, sem o JSON cru" do
      stub_request(:put, "#{ml}/items/MLB1").to_return(status: 400, body: { message: "Validation error", cause: [ { code: "item.attributes.invalid", message: "Attribute [COLOR] is not valid" } ] }.to_json)
      post "/api/items/MLB1/specs", params: { account_id: account.id, confirm: true, values: { MAIN_COLOR: { value_id: "52049" } } }, headers: auth_headers(admin), as: :json
      expect(json.to_s).to include("Attribute [COLOR] is not valid")
      expect(json.to_s).not_to include("item.attributes.invalid")
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

  describe "variações do mesmo anúncio pai" do
    before do
      account.ml_items.find_by(item_id: "MLB1").update!(family_id: "F1", listing_type_id: "gold_special", sku: "BR01")
      create(:ml_item, ml_account: account, item_id: "MLB2", family_id: "F1", listing_type_id: "gold_special", sku: "BR02", price: 74.9)
      create(:ml_item, ml_account: account, item_id: "MLB3", family_id: "F1", listing_type_id: "gold_special", sku: "BR03", price: 74.9)
      create(:ml_item, ml_account: account, item_id: "MLB4", family_id: "F1", listing_type_id: "gold_pro", sku: "BR01")          # outro tipo: fora
      create(:ml_item, ml_account: account, item_id: "MLB5", family_id: "F1", listing_type_id: "gold_special", catalog_listing: true) # catálogo: fora
      create(:ml_item, ml_account: account, item_id: "MLB6", family_id: "F9", listing_type_id: "gold_special", sku: "BR01")        # outra família: fora
    end

    it "lista só as variações do mesmo pai e o Ciente vale para elas quando pedido" do
      get "/api/items/MLB1/variations", params: { account_id: account.id }, headers: auth_headers(member)
      expect(json).to include("count" => 2)
      expect(json["items"].map { |i| i["item_id"] }).to eq(%w[MLB2 MLB3])

      post "/api/items/MLB1/suggestion_acks", params: { account_id: account.id, key: "vídeo:Adicionar vídeo", kind: "aguardar" }, headers: auth_headers(member)
      expect(account.abc_suggestion_acks.pluck(:item_id)).to eq([ "MLB1" ])

      post "/api/items/MLB1/suggestion_acks", params: { account_id: account.id, key: "vídeo:Adicionar vídeo", kind: "aguardar", apply_to_variations: true }, headers: auth_headers(member)
      expect(json).to include("applied" => 3)
      expect(json["message"]).to include("outras 2 variação")
      expect(account.abc_suggestion_acks.pluck(:item_id)).to match_array(%w[MLB1 MLB2 MLB3])
    end

    it "preço sugerido para todas as variações: publica em cada uma; a que já está no preço conta como feita" do
      stub_request(:get, "#{ml}/items/MLB1").to_return(status: 200, body: item.merge("price" => 74.9).to_json)
      stub_request(:get, "#{ml}/items/MLB2").to_return(status: 200, body: { id: "MLB2", price: 74.9 }.to_json)
      stub_request(:get, "#{ml}/items/MLB3").to_return(status: 200, body: { id: "MLB3", price: 81.57 }.to_json)
      put1 = stub_request(:put, "#{ml}/items/MLB1").to_return(status: 200, body: "{}")
      put2 = stub_request(:put, "#{ml}/items/MLB2").with(body: { price: 81.57 }.to_json).to_return(status: 200, body: "{}")
      put3 = stub_request(:put, "#{ml}/items/MLB3").to_return(status: 200, body: "{}")

      post "/api/items/MLB1/price", params: { account_id: account.id, price: 81.57, confirm: true, apply_to_variations: true }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(put1).to have_been_requested.once
      expect(put2).to have_been_requested.once
      expect(put3).not_to have_been_requested # já estava em 81,57
      expect(json["variations"].map { |v| [ v["item_id"], v["ok"] ] }).to eq([ [ "MLB2", true ], [ "MLB3", true ] ])
      expect(json["message"]).to include("preço aplicado em 2 de 2")
      expect(account.abc_suggestion_acks.where(key: AbcSuggestionAck::PRICE_KEY).pluck(:item_id)).to match_array(%w[MLB1 MLB2])
    end

    it "ficha técnica para todas as variações: copia só o que é comum e só o que falta em cada uma" do
      stub_request(:get, "#{ml}/categories/MLB29888/attributes").to_return(status: 200, body: [
        { id: "SKIN_TYPE", name: "Tipo de pele", value_type: "string", tags: {}, relevance: 1 },
        { id: "COLOR", name: "Cor", value_type: "string", tags: { allow_variations: true }, relevance: 1 }
      ].to_json)
      stub_request(:get, "#{ml}/items/MLB2").to_return(status: 200, body: { id: "MLB2", category_id: "MLB29888", attributes: [] }.to_json)
      stub_request(:get, "#{ml}/items/MLB3").to_return(status: 200, body: { id: "MLB3", category_id: "MLB29888", attributes: [ { id: "SKIN_TYPE", value_name: "Oleosa" } ] }.to_json)
      put1 = stub_request(:put, "#{ml}/items/MLB1").with(body: { attributes: [ { id: "SKIN_TYPE", value_name: "Todos" }, { id: "COLOR", value_name: "Bege" } ] }.to_json).to_return(status: 200, body: "{}")
      put2 = stub_request(:put, "#{ml}/items/MLB2").with(body: { attributes: [ { id: "SKIN_TYPE", value_name: "Todos" } ] }.to_json).to_return(status: 200, body: "{}")
      put3 = stub_request(:put, "#{ml}/items/MLB3").to_return(status: 200, body: "{}")

      post "/api/items/MLB1/specs", params: { account_id: account.id, confirm: true, apply_to_variations: true,
                                              values: { SKIN_TYPE: { value_name: "Todos" }, COLOR: { value_name: "Bege" } } }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(put1).to have_been_requested.once
      expect(put2).to have_been_requested.once # a cor (atributo de variação) não é copiada
      expect(put3).not_to have_been_requested  # já tinha tipo de pele
      expect(json["variations"].map { |v| [ v["item_id"], v["ok"], v["published"] ] }).to eq([ [ "MLB2", true, 1 ], [ "MLB3", true, 0 ] ])
    end
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
