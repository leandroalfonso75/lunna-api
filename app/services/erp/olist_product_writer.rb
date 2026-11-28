# Envia ao Olist a edição de uma ficha ("Salvar no Lunna e ERP", 28/11/2026). Só é chamado quando o usuário confirma.
#
# Para não apagar nada que o Lunna não conhece, relê o cadastro no Olist logo antes, troca só o que mudou e manda o
# objeto inteiro (a API não garante atualização parcial). O custo (precoCusto) vai como está no Olist: o custo do
# produto é o PEPS do lançamento do estoque e não é alterado por aqui. Cada chamada fica em OlistChange (auditoria).
#
# O que a API do Olist aceita: dados do produto (PUT /produtos/{id}), SKU/GTIN/preço das variações
# (PUT /produtos/{id}/variacoes/{idVariacao}) e a composição do kit (PUT /produtos/{id}/kit). Não aceita pela edição:
# o valor da variação (grade), marca/categoria/fornecedor por nome (o Olist pede o id) e imagens (só por endereço
# público da internet, e as fotos do Lunna local não têm um).
module Erp
  class OlistProductWriter
    # campo da ficha → caminho no corpo do Olist
    PATHS = {
      "name" => %w[descricao], "sku" => %w[sku], "gtin" => %w[gtin], "unit" => %w[unidade], "ncm" => %w[ncm],
      "cest" => %w[codigoEspecificadorSubstituicaoTributaria], "icms_origin" => %w[origem], "warranty" => %w[garantia],
      "notes" => %w[observacoes], "description" => %w[descricaoComplementar], "price" => %w[precos preco],
      "weight_net" => %w[dimensoes pesoLiquido], "weight_gross" => %w[dimensoes pesoBruto], "package_width" => %w[dimensoes largura],
      "package_height" => %w[dimensoes altura], "package_length" => %w[dimensoes comprimento], "stock_control" => %w[estoque controlar],
      "min_stock" => %w[estoque minimo], "max_stock" => %w[estoque maximo], "location" => %w[estoque localizacao],
      "preparation_days" => %w[estoque diasPreparacao], "seo_title" => %w[seo titulo], "seo_description" => %w[seo descricao],
      "keywords" => %w[seo keywords], "video_url" => %w[seo linkVideo]
    }.freeze
    BODY_KEYS = %w[sku descricao descricaoComplementar unidade unidadePorCaixa ncm gtin origem codigoEspecificadorSubstituicaoTributaria
                   garantia observacoes marca categoria precos dimensoes tributacao seo fornecedores estoque].freeze
    NOT_SENDABLE = {
      "brand" => "o Olist pede a marca pelo código dele; troque a marca no Olist",
      "category" => "o Olist pede a categoria pelo código dele; troque a categoria no Olist",
      "supplier" => "o Olist pede o fornecedor pelo código dele; troque o fornecedor no Olist",
      "images" => "o Olist só recebe imagens por um endereço público na internet, e as fotos do Lunna local não têm um",
      "variation_attrs" => "o Olist não permite trocar o valor da variação (cor, tom, voltagem...) pela integração"
    }.freeze

    def initialize(company, user:, client: nil)
      @company = company
      @user = user
      @client = client || Olist::Client.new(company.olist_connection)
    end

    def self.sendable?(field) = PATHS.key?(field)

    # product: a ficha (já com os valores novos). fields: campos do produto que mudaram; variations: { erp_id => { "sku", "gtin", "price" } };
    # kits: { erp_id => [ { "sku", "quantity" } ] } (kit do produto ou de variação). => [ { what:, ok:, error: } ]
    def call(product, fields:, variations: {}, kits: {})
      results = []
      product_fields = fields & PATHS.keys
      results << send_product(product, product_fields) if product_fields.any?
      variations.each { |vid, changes| results << send_variation(product, vid, changes) }
      kits.each { |kid, comps| results << send_kit(kid, comps) }
      results
    end

    private

    def send_product(product, fields)
      audit("product", product.erp_id, fields.to_h { |f| [ f, product.public_send(f) ] }) do
        base = @client.product(product.erp_id)
        body = body_from(base)
        fields.each { |f| set(body, PATHS[f], erp_value(f, product.public_send(f))) }
        @client.update_product(product.erp_id, body)
        { what: "produto", fields: fields }
      end
    end

    def send_variation(product, vid, changes)
      audit("variation", vid, changes) do
        base = @client.product(vid)
        body = body_from(base)
        body["sku"] = changes["sku"] if changes.key?("sku")
        body["gtin"] = changes["gtin"].to_s if changes.key?("gtin")
        set(body, %w[precos preco], changes["price"].to_f) if changes.key?("price")
        @client.update_variation(product.erp_id, vid, body)
        { what: "variação #{changes['sku'] || base['sku']}", fields: changes.keys }
      end
    end

    def send_kit(kit_id, comps)
      ids = @company.olist_products.where(sku: comps.map { |c| c["sku"] }, status: "A").pluck(:sku, :olist_id).to_h
      missing = comps.map { |c| c["sku"] } - ids.keys
      return { what: "kit", ok: false, error: "componente sem cadastro ativo no Olist: #{missing.join(', ')}" } if missing.any?

      items = comps.map { |c| { produto: { id: ids[c["sku"]] }, quantidade: c["quantity"].to_f } }
      audit("kit", kit_id, { "components" => comps }) do
        @client.update_kit(kit_id, items)
        { what: "kit", fields: [ "kit_components" ] }
      end
    end

    # O cadastro lido do Olist, só com o que o PUT aceita (marca/categoria pelo id; custo como está).
    def body_from(base)
      b = base.to_h.deep_stringify_keys.slice(*BODY_KEYS)
      b["marca"] = b["marca"] && b["marca"]["id"] ? { "id" => b["marca"]["id"] } : nil
      b["categoria"] = b["categoria"] && b["categoria"]["id"] ? { "id" => b["categoria"]["id"] } : nil
      b["estoque"] = b["estoque"].to_h.slice("controlar", "sobEncomenda", "minimo", "maximo", "diasPreparacao", "localizacao") if b["estoque"]
      b["fornecedores"] = Array(b["fornecedores"]).select { |f| f["id"].to_i.positive? }.map { |f| f.slice("id", "codigoProdutoNoFornecedor", "padrao") }
      if b.dig("dimensoes", "embalagem")
        b["dimensoes"]["embalagem"] = b["dimensoes"]["embalagem"].slice("id", "tipo")
      end
      b.compact
    end

    def set(body, path, value)
      *parents, key = path
      node = parents.reduce(body) { |h, k| h[k] = (h[k].is_a?(Hash) ? h[k] : {}) }
      node[key] = value
    end

    def erp_value(field, value)
      case field
      when "keywords" then value.to_s.split(",").map(&:strip).compact_blank
      when "ncm" then (d = value.to_s.gsub(/\D/, "")).size == 8 ? "#{d[0, 4]}.#{d[4, 2]}.#{d[6, 2]}" : d
      when "price", "weight_net", "weight_gross", "min_stock", "max_stock" then value.nil? ? 0 : value.to_f
      when "package_width", "package_height", "package_length", "preparation_days", "icms_origin" then value.to_i
      when "stock_control" then value == true
      else value.to_s
      end
    end

    def audit(kind, olist_id, request)
      change = OlistChange.create!(company: @company, user: @user, olist_product_id: olist_id, kind: kind, request: request.as_json)
      result = yield
      change.update!(status: "done", response: result.as_json)
      result.merge(ok: true)
    rescue Olist::Client::Error => e
      change&.update!(status: "failed", error: e.message.to_s.truncate(500))
      { what: kind, ok: false, error: e.message.to_s.truncate(300) }
    end
  end
end
