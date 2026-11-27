# "Criar Produto com IA" (26/11/2026): a IA preenche o rascunho do produto a partir das evidências (Catalog::Evidence).
#
# Regras de criação adaptadas das que o usuário já usa nas fichas de anúncio:
#   - quem preenche o quê: o usuário cuida de referências, SKU/EAN/estoque das variações, preço, custo, medidas da
#     embalagem de fábrica, garantia, regulatório e observações; a IA cuida de nome, marca, linha, modelo, categoria,
#     condição, formato de venda, títulos, descrição, ficha técnica, palavras-chave/SEO e medidas da embalagem só quando
#     estão nas referências. A IA NUNCA sobrescreve um campo que o usuário já preencheu (vai para ai_suggestions);
#   - evidências antes da persuasão: só entra o que está nas referências; o resto vai para o "Para conferir";
#   - campos fiscais (NCM, CEST, origem, tipo SPED): só sugestão, o usuário confirma;
#   - títulos até 60 caracteres, distintos entre si (o ML inativa duplicados); descrição em texto simples, seções em
#     maiúsculas, sem links/contatos/emojis.
# Promoção, tipo de anúncio e envio ficam para a publicação do anúncio (fora daqui).
module Catalog
  class AiDraft
    class Error < StandardError; end

    AI_FIELDS = %w[name brand line model category condition sale_format description keywords seo_title seo_description].freeze
    FISCAL = %w[ncm cest icms_origin sped_item_type].freeze
    SECTIONS = [ "APRESENTAÇÃO", "DIFERENCIAIS", "MODO DE USO", "CONTEÚDO DA EMBALAGEM", "ESPECIFICAÇÕES", "PRECAUÇÕES", "COMPOSIÇÃO" ].freeze

    # replace: false (padrão) só preenche o que está vazio; o que já tem valor (digitado ou editado pelo usuário) fica, e a
    # alternativa da IA vai para ai_suggestions["kept"]. replace: true ("Gerar de novo substituindo os textos") troca os
    # textos da IA (nome, títulos, descrição, ficha, SEO...), mas nunca preço, SKU, EAN, estoque, medidas do usuário.
    def self.call(product, http: nil, ml_client: nil, chat: Ai::JsonChat, replace: false) = new(product, http, ml_client, chat, replace).call

    def initialize(product, http, ml_client, chat, replace = false)
      @replace = replace
      @product = product
      @http = http
      @ml_client = ml_client
      @chat = chat
    end

    def call
      evidence = Catalog::Evidence.call(@product, http: @http, ml_client: @ml_client)
      if evidence.blocks.empty? && evidence.images.empty?
        raise Error, "Informe ao menos uma referência: link, texto, foto ou SKUs que compõem o kit."
      end

      data = @chat.call(@product.company, system: system_prompt, user: user_prompt(evidence), images: evidence.images, max_tokens: 6000)
      apply(data, evidence)
      @product
    rescue Ai::JsonChat::Error => e
      raise Error, e.message
    end

    private

    def system_prompt
      <<~TXT
        Você é o assistente de cadastro de produtos do Lunna (e-commerce brasileiro, Mercado Livre). Escreva em português do Brasil.
        Sua tarefa: montar o rascunho do cadastro de UM produto a partir SOMENTE das evidências recebidas.

        MÉTODO: evidências → diagnóstico → texto → verificação.
        1. Evidências antes da persuasão: só use atributos confirmados ou declarados nas evidências. O que for inferido,
           incerto ou contraditório entre fontes fica FORA dos textos e vai para "para_conferir". Nunca deduza voltagem,
           material, potência, temperatura, composição ou certificação pela foto. Não invente certificações, avaliações,
           garantia, resultados garantidos, nem "profissional", "original", "premium" sem suporte. Não transfira dados de um
           produto para outro. Não cite marcas de concorrentes. Sem depoimentos ou antes/depois.
        2. Títulos: gere 4 títulos DIFERENTES entre si (ordem e foco diferentes), cada um com no máximo 60 caracteres
           contando espaços. Estrutura: produto + diferencial confirmado + benefício/uso + palavra-chave de busca.
           Sem erros de ortografia, sem prometer ranking ou vendas, sem caixa alta inteira.
        3. Descrição: texto simples, sem links, telefone, e-mail, emojis ou HTML. Seções com o título em MAIÚSCULAS, nesta
           ordem quando houver dado: #{SECTIONS.join(', ')}. Linguagem objetiva e comercial: característica → utilidade → benefício.
        4. Ficha técnica: pares atributo/valor só com dados das evidências (marca, modelo, cor, voltagem, material, medidas,
           peso, conteúdo, etc.).
        5. Embalagem: largura, altura e comprimento em cm INTEIROS (arredonde para cima) e peso bruto em kg, SOMENTE se
           estiverem nas evidências e forem do próprio produto; senão deixe null. Em kit, deixe null (a embalagem de um
           componente não é a do kit).
        6. Fiscal (só sugestão, o usuário confirma): NCM (8 dígitos) e CEST quando houver segurança; origem ICMS (0 a 8) só
           se as evidências indicarem nacional/importado; tipo do item SPED (normalmente "Mercadoria para Revenda").
        7. Kit: quando houver SKUs de referência, o produto é o conjunto desses itens; descreva o que vem no kit e use os
           dados de cada componente sem misturar atributos entre eles: cor, voltagem, material e medidas pertencem ao
           componente de onde vieram (ex.: a cor de um acessório não é a cor do produto principal). Nos títulos, só use
           um atributo junto do item a que ele pertence. Não mencione códigos internos de atributos (ex.: GIFTABLE).
        8. Variações: se as evidências mostrarem variações (cor, voltagem, tamanho...) e o usuário ainda não criou nenhuma,
           sugira o eixo e os valores (sem SKU, EAN, preço ou estoque).

        Responda SOMENTE com um JSON neste formato:
        {"name": "nome do produto para o cadastro (até 120 caracteres)", "brand": "", "line": "", "model": "",
         "category": "caminho completo da categoria no Mercado Livre", "condition": "novo|usado|recondicionado",
         "sale_format": "unidade|kit|pack", "titles": ["", "", "", ""], "description": "",
         "technical_sheet": [{"name": "", "value": ""}], "keywords": "palavras separadas por vírgula",
         "seo_title": "", "seo_description": "",
         "package": {"width": null, "height": null, "length": null, "weight": null, "source": "trecho da evidência"},
         "fiscal": {"ncm": null, "cest": null, "icms_origin": null, "sped_item_type": null, "why": ""},
         "variations": {"axes": [], "values": [{"Cor": "Vermelho"}]},
         "para_conferir": ["o que foi omitido e por quê, divergências entre fontes, o que o usuário precisa confirmar"]}
        Campos sem evidência: "" ou null. Nunca preencha preço, custo, SKU, EAN ou estoque.
      TXT
    end

    def user_prompt(evidence)
      kind = { "simple" => "Produto simples", "variations" => "Produto com variações", "kit" => "Kit" }[@product.kind]
      filled = filled_by_user
      variations = @product.variations.map { |v| v["attrs"].map { |k, x| "#{k}: #{x}" }.join(", ") }.compact_blank
      <<~TXT
        TIPO: #{kind}#{@product.kind == 'kit' && @product.no_reference_skus ? ' (sem SKUs de referência: use as referências livres)' : ''}#{@product.kind == 'kit' && @product.use_component_references && !@product.no_reference_skus && @product.component_skus.any? ? ' (referências = os produtos que formam o kit: use as descrições, fichas técnicas e especificações de cada componente, sem misturar atributos entre eles)' : ''}
        #{variation_kit_text}
        #{"VARIAÇÕES JÁ CRIADAS PELO USUÁRIO (#{@product.variation_axes.join(' / ')}): #{variations.join(' | ')}" if variations.any?}
        #{"JÁ PREENCHIDO PELO USUÁRIO (não mude, use como fato): #{filled}" if filled.present?}

        EVIDÊNCIAS:
        #{evidence.blocks.join("\n\n")}
        #{"\nAVISOS DA COLETA: #{evidence.warnings.join(' | ')}" if evidence.warnings.any?}
        #{evidence.images.any? ? "\n#{evidence.images.size} foto(s) #{photos_origin} anexada(s): use para identificar o produto e o que vem nele, mas não deduza especificações técnicas pela foto." : ''}
      TXT
    end

    # Kit com variações: diz à IA que o produto tem uma variação por variação do pai, cada uma junto do mesmo simples. Os
    # textos falam do kit em geral (a variação aparece na grade); a voltagem/cor é da variação, não do simples.
    def variation_kit_text
      return "" unless @product.variation_kit?

      simple = @product.kit_simple_sku
      lines = @product.variations.map { |v| "#{v['attrs'].values.join(' / ')} = #{Array(v['components']).map { |c| c['sku'] }.join(' + ')} + #{simple}" }
      "KIT COM VARIAÇÕES: cada variação do produto #{@product.kit_parent_sku} (#{@product.variation_axes.join(' / ')}) vem junto do produto " \
        "simples #{simple}. Kits: #{lines.join(' | ')}. Escreva nome, títulos e descrição do kit em geral (sem fixar uma variação); " \
        "o atributo da variação (#{@product.variation_axes.join(' / ')}) é do produto com variações, nunca do produto simples."
    end

    def photos_origin
      kit_photos = @product.kind == "kit" && @product.use_component_photos && !@product.no_reference_skus && @product.component_skus.any?
      kit_photos ? "dos produtos que formam o kit (anúncios de cada componente; cada foto mostra um componente, não o kit montado)" : "do produto"
    end

    def filled_by_user
      { "nome" => @product.name, "marca" => @product.brand, "modelo" => @product.model, "garantia" => @product.warranty,
        "Anvisa" => @product.regulatory.to_h["anvisa"] }.compact_blank.map { |k, v| "#{k}: #{v}" }.join("; ")
    end

    def apply(data, evidence)
      kept = {}
      AI_FIELDS.each do |field|
        value = data[field].is_a?(String) ? data[field].strip : data[field]
        next if value.blank?

        value = value.downcase if %w[condition sale_format].include?(field)
        next if field == "condition" && CatalogProduct::CONDITIONS.exclude?(value)
        next if field == "sale_format" && CatalogProduct::SALE_FORMATS.exclude?(value)
        value = clean_description(value) if field == "description"
        current = @product.public_send(field)
        user_set = current.present? && !(field == "condition" && current == "novo") && !(field == "sale_format" && current == "unidade")
        # o que o usuário já digitou não é trocado: a sugestão da IA fica guardada para ele usar se quiser
        if user_set && !@replace && current.to_s != value.to_s
          kept[field] = value
        else
          @product.public_send("#{field}=", value)
        end
      end

      review = Array(data["para_conferir"]).map { |x| x.to_s.squish }.compact_blank
      review.concat(evidence.warnings)
      titles = valid_titles(data["titles"], review)
      if @product.titles.present? && !@replace
        kept["titles"] = titles if titles.any? && titles != @product.titles
      else
        @product.titles = titles
      end
      sheet = Array(data["technical_sheet"]).filter_map { |r| { "name" => r["name"].to_s, "value" => r["value"].to_s } if r.is_a?(Hash) }
      if @product.technical_sheet.present? && !@replace
        kept["technical_sheet"] = sheet if sheet.any?
      elsif sheet.any?
        @product.technical_sheet = sheet
      end
      apply_package(data["package"], review)
      apply_variations(data["variations"])
      fiscal = data["fiscal"].is_a?(Hash) ? data["fiscal"].slice(*FISCAL, "why").compact_blank : {}
      fiscal["ncm"] = fiscal["ncm"].to_s.gsub(/\D/, "") if fiscal["ncm"]
      fiscal.delete("ncm") if fiscal["ncm"] && fiscal["ncm"].size != 8
      fiscal.delete("icms_origin") unless (0..8).cover?(Integer(fiscal["icms_origin"], exception: false) || -1)

      @product.ai_suggestions = { "fiscal" => fiscal, "kept" => kept }.compact_blank
      @product.ai_review = review.uniq.first(30)
      @product.ai_generated_at = Time.current
      @product.ai_error = nil
      @product.status = "em_revisao" if @product.status == "rascunho"
    end

    # títulos: até 60 caracteres e distintos entre si; os que passam disso não entram (e o usuário é avisado)
    def valid_titles(list, review)
      titles = Array(list).map { |t| t.to_s.squish }.compact_blank
      long = titles.select { |t| t.size > CatalogProduct::TITLE_MAX }
      review << "#{long.size} título(s) da IA passaram de #{CatalogProduct::TITLE_MAX} caracteres e foram descartados." if long.any?
      ok = (titles - long).uniq { |t| t.downcase }
      review << "A IA não devolveu títulos válidos; escreva pelo menos um." if ok.empty?
      ok.first(4)
    end

    def clean_description(text)
      text.gsub(%r{https?://\S+|www\.\S+}i, "").gsub(/\S+@\S+\.\S+/, "")
          .gsub(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/, "").gsub(/<[^>]+>/, "").gsub(/[ \t]+\n/, "\n").strip
    end

    def apply_package(pkg, review)
      return if @product.package_source == "usuario" # medidas digitadas pelo usuário mandam

      # kit: a embalagem é a do conjunto, nunca a de um componente (26/11/2026: a IA usou a caixa do difusor como a do
      # kit secador + difusor); só o usuário informa
      if @product.kind == "kit"
        @product.package_source = "nao_encontrado"
        review << "Kit: informe as medidas e o peso da embalagem do conjunto (a de cada componente não serve para o kit)."
        return
      end

      pkg = pkg.is_a?(Hash) ? pkg : {}
      dims = %w[width height length].map { |k| Float(pkg[k], exception: false) }
      weight = Float(pkg["weight"], exception: false)
      if dims.all? { |d| d&.positive? }
        @product.package_width, @product.package_height, @product.package_length = dims.map { |d| d.ceil }
        @product.weight_gross = weight if weight&.positive?
        @product.package_source = "ia"
      else
        @product.package_source = "nao_encontrado"
        review << "Medidas e peso da embalagem não foram encontrados nas referências: informe-os."
      end
    end

    def apply_variations(var)
      return unless @product.kind == "variations" && @product.variations.empty? && var.is_a?(Hash)

      axes = Array(var["axes"]).map(&:to_s).compact_blank.first(3)
      values = Array(var["values"]).select { |v| v.is_a?(Hash) }.first(CatalogProduct::MAX_VARIATIONS)
      return if axes.empty? || values.empty?

      @product.variation_axes = axes
      @product.variations = values.map { |v| { "attrs" => v.slice(*axes) } }
    end
  end
end
