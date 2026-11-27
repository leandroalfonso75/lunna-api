require "rails_helper"

RSpec.describe "Criar Produto com IA (/api/catalog_products)", type: :request do
  let(:company) { create(:company, :with_ai) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }
  let(:openrouter) { "https://openrouter.ai/api/v1/chat/completions" }

  def ai_reply(content)
    stub_request(:post, openrouter).to_return(status: 200, body: { choices: [ { message: { content: content.to_json } } ] }.to_json)
  end

  def olist(sku, name, kind: "S", variation_kind: "N", cost: 10)
    OlistProduct.create!(company: company, olist_id: rand(1..9_999_999), sku: sku, description: name, kind: kind, status: "A",
                         variation_kind: variation_kind, cost_price: cost, price: cost * 2, synced_at: Time.current)
  end

  it "cria o rascunho (só admin), salva campos e valida EAN e SKUs das variações" do
    post "/api/catalog_products", params: { kind: "simple" }, headers: auth_headers(member), as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/catalog_products", params: { kind: "variations", variation_axes: [ "Voltagem" ],
      variations: [ { attrs: { Voltagem: "127V" }, sku: "SEC-127" }, { attrs: { Voltagem: "220V" }, sku: "SEC-220" } ] },
      headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    id = json["id"]
    expect(json["variations"].map { |v| v["attrs"] }).to eq([ { "Voltagem" => "127V" }, { "Voltagem" => "220V" } ])

    patch "/api/catalog_products/#{id}", params: { gtin: "7891234567890" }, headers: auth_headers(admin), as: :json
    expect(json["errors"].join).to include("dígito verificador")

    patch "/api/catalog_products/#{id}", params: { gtin: "7891234567895", price: "129,90".tr(",", "."), package_width: 30 },
      headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("gtin" => "7891234567895", "package_source" => "usuario")

    patch "/api/catalog_products/#{id}", params: { variations: [ { attrs: { Voltagem: "127V" }, sku: "X" }, { attrs: { Voltagem: "220V" }, sku: "X" } ] },
      headers: auth_headers(admin), as: :json
    expect(json["errors"].join).to include("SKU repetido")

    get "/api/catalog_products", headers: auth_headers(member)
    expect(json["products"].first).to include("id" => id, "kind" => "variations", "variations_count" => 2)
  end

  it "variação que é kit: itens comuns + item próprio da variação, sem repetir o comum em cada linha" do
    olist("LS-POSOLTO", "Pó Solto Letty")
    olist("LS-BASE-104", "Base Glow 104")
    product = company.catalog_products.create!(kind: "variations", variation_axes: [ "Tom" ],
      common_components: [ { sku: "LS-POSOLTO", quantity: 1 } ],
      variations: [ { attrs: { Tom: "104" }, sku: "LS-KIT-104", kit: true, components: [ { sku: "LS-BASE-104", quantity: 1 } ] },
                    { attrs: { Tom: "105" }, sku: "LS-BASE-105" } ])

    expect(product.components_for(product.variations[0])).to contain_exactly({ "sku" => "LS-POSOLTO", "quantity" => 1.0 }, { "sku" => "LS-BASE-104", "quantity" => 1.0 })
    expect(product.components_for(product.variations[1])).to eq([]) # variação sem "é kit" é item único

    get "/api/catalog_products/#{product.id}", headers: auth_headers(admin)
    expect(json["components_info"].keys).to contain_exactly("LS-POSOLTO", "LS-BASE-104")

    product.kit_components = [ { sku: "LS-KIT-104", quantity: 1 } ]
    expect(product).not_to be_valid # o kit não pode conter o próprio SKU
  end

  it "busca SKUs para compor o kit (sem o pai de variações)" do
    olist("LS-DIF", "Difusor de Cachos Universal")
    olist("LS-SEC", "Secador pai", kind: "S", variation_kind: "P")

    get "/api/catalog_products/sku_search", params: { q: "LS-" }, headers: auth_headers(member)
    expect(json["items"].map { |i| i["sku"] }).to eq([ "LS-DIF" ])
  end

  it "a IA preenche o rascunho só com as evidências: kit pelos SKUs, títulos ≤ 60, fiscal como sugestão, sem trocar o que o usuário digitou" do
    olist("LS-SCN01-220", "Secador Mondial SCN-01 220V")
    olist("LS-DIF", "Difusor de Cachos Universal")
    product = company.catalog_products.create!(kind: "kit", brand: "Mondial", kit_components: [ { sku: "LS-SCN01-220", quantity: 1 }, { sku: "LS-DIF", quantity: 1 } ])
    long = "x" * 61
    request = ai_reply(
      name: "Kit Secador Mondial SCN-01 220V + Difusor", brand: "Outra", category: "Beleza > Secadores", condition: "Novo", sale_format: "kit",
      titles: [ "Kit Secador Mondial SCN-01 220V com Difusor de Cachos", long, "Secador Mondial SCN-01 + Difusor Universal 220V", "Kit Secador Mondial SCN-01 220V com Difusor de Cachos" ],
      description: "APRESENTAÇÃO\nKit com secador e difusor. Veja em https://loja.com 😀", technical_sheet: [ { name: "Voltagem", value: "220V" } ],
      package: { width: 12, height: 26, length: 21, weight: 0.23 }, fiscal: { ncm: "8516.31.00", icms_origin: 0, why: "secador" },
      para_conferir: [ "Potência não informada nas referências." ]
    )

    post "/api/catalog_products/#{product.id}/generate", headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(request.with { |req| JSON.parse(req.body)["messages"][1]["content"].include?("SKU DE REFERÊNCIA LS-DIF") }).to have_been_made

    expect(json["name"]).to eq("Kit Secador Mondial SCN-01 220V + Difusor")
    expect(json["brand"]).to eq("Mondial") # digitado pelo usuário: fica
    expect(json["ai_suggestions"]["kept"]).to include("brand" => "Outra")
    expect(json["titles"]).to eq([ "Kit Secador Mondial SCN-01 220V com Difusor de Cachos", "Secador Mondial SCN-01 + Difusor Universal 220V" ])
    expect(json["description"]).not_to include("http", "😀")
    expect(json["ncm"]).to be_nil
    expect(json["ai_suggestions"]["fiscal"]).to include("ncm" => "85163100", "icms_origin" => 0)
    expect(json["package_source"]).to eq("nao_encontrado") # kit: medidas de um componente não viram as do kit
    expect(json["package_width"]).to be_nil
    expect(json["ai_review"]).to include("Potência não informada nas referências.", a_string_including("passaram de 60"), a_string_including("embalagem do conjunto"))
    expect(json["status"]).to eq("em_revisao")
  end

  it "sem nenhuma referência a IA não é chamada" do
    product = company.catalog_products.create!(kind: "kit", no_reference_skus: true)

    post "/api/catalog_products/#{product.id}/generate", headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json["errors"].first).to include("Informe ao menos uma referência")
    expect(a_request(:post, openrouter)).not_to have_been_made
  end

  it "anexa imagem de referência e manda para o modelo de visão" do
    product = company.catalog_products.create!(kind: "simple")
    png = "data:image/png;base64,#{Base64.strict_encode64("\x89PNG\r\n\x1A\nfake".b)}"

    post "/api/catalog_products/#{product.id}/assets", params: { data: png, name: "foto.png" }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    asset_id = json["id"]

    request = ai_reply(name: "Produto", titles: [ "Produto de teste" ], para_conferir: [])
    post "/api/catalog_products/#{product.id}/generate", headers: auth_headers(admin), as: :json
    expect(request.with { |req| JSON.parse(req.body)["messages"][1]["content"].is_a?(Array) }).to have_been_made

    delete "/api/catalog_product_assets/#{asset_id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:no_content)
  end

  it "link interno não é aberto (só endereços públicos)" do
    product = company.catalog_products.create!(kind: "simple", references: { links: [ "http://127.0.0.1:3000/up" ], text: "Secador vermelho" })
    ai_reply(name: "Secador", titles: [ "Secador vermelho" ], para_conferir: [])

    post "/api/catalog_products/#{product.id}/generate", headers: auth_headers(admin), as: :json
    expect(json["ai_review"]).to include(a_string_including("Link ignorado"))
  end

  it "kit com 'usar como referências os produtos do kit': ignora links e texto e usa descrição e ficha dos componentes" do
    olist("LS-DIF", "Difusor de Cachos Universal")
    account = create(:ml_account, company: company)
    create(:ml_item, item_id: "MLB900", ml_account: account, title: "Difusor Cachos Universal", sku: "LS-DIF", sold_quantity: 10)
    client = instance_double(Ml::Client,
      item_full: { "attributes" => [ { "id" => "MATERIAL", "name" => "Material", "value_name" => "Plástico" } ] },
      item_description: { "plain_text" => "Difusor universal que encaixa na maioria dos secadores." })
    product = company.catalog_products.create!(kind: "kit", use_component_references: true, kit_components: [ { sku: "LS-DIF", quantity: 1 } ],
      references: { links: [ "https://exemplo.com/produto" ], text: "texto que deve ser ignorado" })

    evidence = Catalog::Evidence.call(product, ml_client: client)
    text = evidence.blocks.join("\n")
    expect(text).to include("Material: Plástico", "descrição do anúncio: Difusor universal que encaixa")
    expect(text).not_to include("texto que deve ser ignorado", "LINK https://exemplo.com")
    expect(a_request(:get, "https://exemplo.com/produto")).not_to have_been_made

    product.update!(use_component_references: false)
    stub_request(:get, "https://exemplo.com/produto").to_return(status: 200, body: "<p>Página do produto</p>")
    allow(Resolv).to receive(:getaddresses).and_return([ "93.184.216.34" ])
    text = Catalog::Evidence.call(product, ml_client: client).blocks.join("\n")
    expect(text).to include("texto que deve ser ignorado", "Página do produto")
    expect(text).not_to include("descrição do anúncio")
  end

  describe "kit = 1 produto com variações + 1 produto simples" do
    def child(parent, sku, name)
      OlistProduct.create!(company: company, olist_id: rand(1..9_999_999), sku: sku, description: name, kind: "S", status: "A",
                           variation_kind: "V", parent_olist_id: parent.olist_id, cost_price: 80, price: 200, synced_at: Time.current)
    end

    it "confere os SKUs, importa as variações do pai, deduz o tipo de variação e sugere os SKUs no padrão dos kits" do
      olist("LS-DIF", "Difusor Universal", cost: 7.6)
      pai = olist("LS-SCN01", "Secador Mondial SCN-01", kind: "V", variation_kind: "P")
      child(pai, "LS-SCN01-110", "Secador Mondial SCN-01 - 127V")
      child(pai, "LS-SCN01-220", "Secador Mondial SCN-01 - 220V")

      get "/api/catalog_products/kit_parts", params: { simple: "LS-DIF", parent: "LS-SCN01" }, headers: auth_headers(member)
      expect(json["simple"]).to include("ok" => true, "name" => "Difusor Universal")
      expect(json["parent"]).to include("ok" => true)
      expect(json["axis"]).to eq("Voltagem")
      expect(json["children"].map { |c| [ c["sku"], c["value"] ] }).to eq([ [ "LS-SCN01-110", "127V" ], [ "LS-SCN01-220", "220V" ] ])
      expect(json["suggested"]).to eq("product_sku" => "LS-SCN01-DIF", "kit_skus" => { "LS-SCN01-110" => "LS-SCN01-DIF-110", "LS-SCN01-220" => "LS-SCN01-DIF-220" })

      get "/api/catalog_products/kit_parts", params: { simple: "LS-SCN01", parent: "LS-SCN01-220" }, headers: auth_headers(member)
      expect(json["simple"]["error"]).to include("produto com variações")
      expect(json["parent"]["error"]).to include("variação de LS-SCN01")
      expect(json["suggested"]).to be_nil
    end

    it "cada variação vira um kit (variação + simples) e a IA recebe a composição de cada kit" do
      olist("LS-DIF", "Difusor Universal")
      pai = olist("LS-SCN01", "Secador Mondial SCN-01", kind: "V", variation_kind: "P")
      child(pai, "LS-SCN01-110", "Secador Mondial SCN-01 - 127V")
      product = company.catalog_products.new(kind: "kit", kit_with_variations: true, kit_simple_sku: "LS-DIF", kit_parent_sku: "LS-SCN01",
        variation_axes: [ "Voltagem" ], common_components: [ { sku: "LS-DIF", quantity: 1 } ],
        variations: [ { attrs: { Voltagem: "127V" }, sku: "LS-SCN01-DIF-110", kit: true, components: [ { sku: "LS-SCN01-110", quantity: 1 } ] },
                      { attrs: { Voltagem: "127V" }, sku: "X", kit: true, components: [] } ])
      expect(product).not_to be_valid # variação repetida: a grade do kit vale como em "Com variações"
      expect(product.errors.full_messages.join).to include("repetidas")

      product.variations = product.variations.first(1)
      product.save!
      expect(product.component_skus).to contain_exactly("LS-DIF", "LS-SCN01-110")
      request = ai_reply(name: "Kit Secador Mondial SCN-01 + Difusor", titles: [ "Kit Secador Mondial SCN-01 com Difusor" ], para_conferir: [])

      post "/api/catalog_products/#{product.id}/generate", headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
      expect(request.with { |req| JSON.parse(req.body)["messages"][1]["content"].then { |c| c.include?("KIT COM VARIAÇÕES") && c.include?("127V = LS-SCN01-110 + LS-DIF") && c.include?("SKU DE REFERÊNCIA LS-SCN01-110") } }).to have_been_made
    end
  end
end
