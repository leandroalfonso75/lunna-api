# Migração dos produtos do ERP (27/11/2026): converte o cadastro de um produto do Olist (GET /produtos/{id}) na ficha
# completa do Lunna (CatalogProduct). Função pura: não chama a API nem grava nada (testável com o JSON do ERP).
#
# - S sem pai → simple; K sem pai → kit (componentes e quantidades); V (pai de variações) → variations, com os eixos
#   tirados da "grade" de cada variação (Cor, Tom, Voltagem...). Variação que é kit (tipo K) vira variação com kit: true
#   e os componentes dela (precisa do cadastro da variação em `children`).
# - Imagens: os anexos na ordem do ERP; as das variações que não repetem as do pai ficam presas à variação.
# - Custo: NÃO vem do ERP. O custo do produto é o PEPS do histórico de entradas (cópia sincronizada), que a importação
#   não toca; o histórico de custos do ERP (`custos`) não é copiado.
# - O que não tem campo próprio na ficha fica em erp_payload (o cadastro do ERP, sem `custos`).
module Erp
  module OlistProductMapper
    ERP_KEY = "olist".freeze

    module_function

    # payload: Hash do GET /produtos/{id}; children: { id da variação => Hash do GET dela } (para kits e imagens).
    # => { attrs: {...}, images: [ { url:, variation_key: } ], warnings: [ "..." ] }
    def call(payload, children: {})
      p = payload.to_h.deep_stringify_keys
      warnings = []
      attrs = base_attrs(p)
      images = urls(p).map { |u| { url: u, variation_key: nil } }

      case kind_of(p)
      when "kit"
        attrs[:kind] = "kit"
        attrs[:sale_format] = "kit"
        attrs[:kit_components] = components(p["kit"])
        warnings << "kit sem componentes no ERP" if attrs[:kit_components].empty?
      when "variations"
        attrs[:kind] = "variations"
        list = Array(p["variacoes"])
        axes = list.flat_map { |v| Array(v["grade"]).map { |g| g["chave"].to_s.strip } }.compact_blank.uniq
        warnings << "mais de 3 tipos de variação no ERP (#{axes.join(', ')}): ficam os 3 primeiros" if axes.size > 3
        attrs[:variation_axes] = axes.first(3)
        parent_urls = images.map { |i| i[:url] }
        attrs[:variations] = list.map do |v|
          vid = v["id"]
          child = children[vid] || children[vid.to_s] || {}
          key = "erp-#{vid}"
          kit = child["tipo"] == "K" || v["tipo"] == "K"
          comps = kit ? components(child["kit"]) : []
          warnings << "variação #{v['sku']} é kit, mas o ERP não trouxe os componentes" if kit && comps.empty?
          (urls(child) - parent_urls).each { |u| images << { url: u, variation_key: key } }
          { "key" => key, "erp_id" => vid, "sku" => v["sku"].to_s.strip.presence, "gtin" => v["gtin"].to_s.strip.presence,
            "price" => money(v.dig("precos", "preco")), "stock" => v.dig("estoque", "quantidade"),
            "attrs" => Array(v["grade"]).to_h { |g| [ g["chave"].to_s.strip, g["valor"].to_s.strip ] }.slice(*attrs[:variation_axes]),
            "kit" => kit, "components" => comps }
        end
        warnings << "produto com variações sem nenhuma variação no ERP" if list.empty?
        warnings << "mais de #{CatalogProduct::MAX_VARIATIONS} variações" if list.size > CatalogProduct::MAX_VARIATIONS
      else
        attrs[:kind] = "simple"
      end

      warnings.concat(checks(attrs, images))
      { attrs: attrs, images: images.uniq { |i| [ i[:url], i[:variation_key] ] }, warnings: warnings }
    end

    # V = pai de variações; K = kit; S = simples. Variação (com pai) não é importada sozinha: vai dentro do pai.
    def kind_of(p)
      return "variations" if p["tipo"] == "V" || p["tipoVariacao"] == "P"
      return "kit" if p["tipo"] == "K"

      "simple"
    end

    def base_attrs(p)
      dims = p["dimensoes"] || {}
      est = p["estoque"] || {}
      seo = p["seo"] || {}
      supplier = Array(p["fornecedores"]).map { |f| f["nome"].to_s.strip }.compact_blank.first
      has_dims = %w[largura altura comprimento].any? { |k| dims[k].to_f.positive? }
      {
        source: "erp", erp_key: ERP_KEY, erp_id: p["id"], status: "pronto",
        name: p["descricao"].to_s.strip.first(120), sku: p["sku"].to_s.strip.presence, gtin: p["gtin"].to_s.strip.presence,
        unit: p["unidade"].to_s.strip.presence || "UN", price: money(p.dig("precos", "preco")),
        weight_net: positive(dims["pesoLiquido"]), weight_gross: positive(dims["pesoBruto"]),
        package_width: int_positive(dims["largura"]), package_height: int_positive(dims["altura"]),
        package_length: int_positive(dims["comprimento"]), package_source: has_dims ? "erp" : nil,
        stock_control: est.key?("controlar") ? est["controlar"] == true : true,
        min_stock: positive(est["minimo"]), max_stock: positive(est["maximo"]),
        location: est["localizacao"].to_s.strip.presence, preparation_days: est["diasPreparacao"].to_i.positive? ? est["diasPreparacao"].to_i : nil,
        ncm: p["ncm"].to_s.strip.presence, icms_origin: p["origem"].to_s =~ /\A\d\z/ ? p["origem"].to_i : nil,
        brand: p.dig("marca", "nome").to_s.strip.presence, category: p.dig("categoria", "caminhoCompleto").to_s.strip.presence,
        description: p["descricaoComplementar"].to_s.strip.presence, warranty: p["garantia"].to_s.strip.presence,
        notes: p["observacoes"].to_s.strip.presence, video_url: seo["linkVideo"].to_s.strip.presence,
        seo_title: seo["titulo"].to_s.strip.presence, seo_description: seo["descricao"].to_s.strip.presence,
        keywords: Array(seo["keywords"]).map(&:to_s).compact_blank.join(", ").presence, supplier: supplier,
        erp_payload: p.except("custos")
      }
    end

    def components(list)
      Array(list).filter_map do |c|
        sku = c.dig("produto", "sku").to_s.strip
        next if sku.empty?

        { "sku" => sku, "quantity" => c["quantidade"].to_f.positive? ? c["quantidade"].to_f : 1.0, "erp_id" => c.dig("produto", "id") }
      end
    end

    def urls(p) = Array(p["anexos"]).filter_map { |a| a["url"].to_s.strip.presence }

    def checks(attrs, images)
      list = []
      list << "sem imagens no ERP" if images.empty?
      list << "sem NCM" if attrs[:ncm].blank?
      list << "sem medidas da embalagem" if attrs[:package_source].nil?
      list << "sem peso" if attrs[:weight_gross].nil? && attrs[:weight_net].nil?
      list << "GTIN inválido (#{attrs[:gtin]})" if attrs[:gtin].present? && !CatalogProduct.valid_gtin?(attrs[:gtin])
      Array(attrs[:variations]).each do |v|
        list << "GTIN inválido na variação #{v['sku']} (#{v['gtin']})" if v["gtin"].present? && !CatalogProduct.valid_gtin?(v["gtin"])
      end
      list
    end

    def money(v) = v.nil? ? nil : v.to_f.round(2)
    def positive(v) = v.to_f.positive? ? v.to_f : nil
    def int_positive(v) = v.to_f.positive? ? v.to_f.round : nil
  end
end
