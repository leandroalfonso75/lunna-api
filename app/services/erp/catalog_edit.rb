# Edição da ficha vinda do ERP (28/11/2026, pedido do usuário). Dois jeitos de salvar:
# - "lunna": só no Lunna. Os campos alterados ficam em local_overrides com o valor do ERP: a atualização automática e o
#   "Reimportar do ERP" não os sobrescrevem em silêncio, e a tela mostra a diferença com a opção de voltar ao do ERP;
# - "erp": no Lunna e no ERP (Erp::OlistProductWriter). O que o ERP aceitou deixa de ser "ajuste do Lunna"; o que ele
#   não aceita (ou se a gravação falhar) fica salvo no Lunna como ajuste, e o resultado diz o que não foi.
# Custo PEPS, histórico de entradas e estoque do kit não são editáveis (regra do Lunna). Nada vai ao Mercado Livre.
module Erp
  class CatalogEdit
    class Invalid < StandardError; end

    FIELDS = %w[name sku gtin unit ncm cest icms_origin brand category warranty supplier notes description price
                weight_net weight_gross package_width package_height package_length stock_control min_stock max_stock
                location preparation_days seo_title seo_description keywords video_url].freeze
    LABELS = {
      "name" => "Nome", "sku" => "SKU", "gtin" => "GTIN/EAN", "unit" => "Unidade", "ncm" => "NCM", "cest" => "CEST",
      "icms_origin" => "Origem", "brand" => "Marca", "category" => "Categoria", "warranty" => "Garantia", "supplier" => "Fornecedor",
      "notes" => "Observações", "description" => "Descrição", "price" => "Preço de venda", "weight_net" => "Peso líquido",
      "weight_gross" => "Peso bruto", "package_width" => "Largura", "package_height" => "Altura", "package_length" => "Comprimento",
      "stock_control" => "Controla estoque", "min_stock" => "Estoque mínimo", "max_stock" => "Estoque máximo",
      "location" => "Localização", "preparation_days" => "Dias para preparar", "seo_title" => "Título SEO",
      "seo_description" => "Descrição SEO", "keywords" => "Palavras-chave", "video_url" => "Vídeo",
      "kit_components" => "Componentes do kit", "images" => "Fotos"
    }.freeze

    Result = Struct.new(:product, :changes, :erp, keyword_init: true)

    def initialize(company, user:, writer: nil)
      @company = company
      @user = user
      @writer = writer
    end

    # params: { "fields" => {campo => valor}, "variations" => {key => {"sku","gtin","price","attrs"}}, "kit_components" => [...],
    #           "variation_components" => {key => [...]}, "photos" => [ids na ordem] }. mode: "lunna" | "erp"; dry_run: só a prévia.
    def call(product, params, mode:, dry_run: false)
      raise Invalid, "Só fichas vindas do ERP são editadas por aqui." unless product.from_erp?

      params = params.to_h.deep_stringify_keys
      changes = diff(product, params)
      return Result.new(product: product, changes: changes, erp: nil) if dry_run || changes.empty?

      before = snapshot(product)
      apply!(product, params, changes)
      erp = mode == "erp" ? send_to_erp(product, changes) : nil
      mark_overrides!(product, changes, before, erp)
      Result.new(product: product.reload, changes: changes, erp: erp)
    end

    # Volta um campo ao valor do ERP (o guardado quando foi ajustado no Lunna; a próxima atualização confirma).
    def reset!(product, field)
      ov = product.local_overrides[field] or raise Invalid, "Este campo não está ajustado no Lunna."
      if FIELDS.include?(field)
        product.public_send("#{field}=", ov["erp_value"])
      elsif field == "kit_components"
        product.kit_components = ov["erp_value"]
      elsif field == "variations"
        product.variations = ov["erp_value"]
      end
      # "images": tira as fotos adicionadas no Lunna; sem o ajuste, a próxima leitura do ERP volta às fotos dele
      product.assets.where(kind: "foto", source_url: nil).delete_all if field == "images"
      product.local_overrides = product.local_overrides.except(field)
      product.save!
      product
    end

    private

    # Lista do que muda: [ { key:, label:, from:, to:, erp: true/false, reason: } ]
    def diff(product, params)
      list = []
      Hash(params["fields"]).slice(*FIELDS).each do |f, v|
        v = normalize(f, v)
        old = product.public_send(f)
        next if same?(old, v)

        list << item(f, LABELS[f], old, v)
      end
      Hash(params["variations"]).each do |key, ch|
        var = product.variations.find { |x| x["key"] == key } or next
        %w[sku gtin price].each do |k|
          next unless ch.key?(k)

          nv = k == "price" ? ch[k].presence&.to_s&.tr(",", ".")&.to_f : ch[k].to_s.strip.presence
          next if same?(var[k], nv)

          list << { key: "variation:#{key}:#{k}", label: "Variação #{var['sku']} · #{{ 'sku' => 'SKU', 'gtin' => 'GTIN', 'price' => 'Preço' }[k]}",
                    from: var[k], to: nv, erp: true, variation: key, attr: k }
        end
        Hash(ch["attrs"]).each do |ax, val|
          next if var["attrs"].to_h[ax].to_s == val.to_s.strip

          list << { key: "variation:#{key}:attrs:#{ax}", label: "Variação #{var['sku']} · #{ax}", from: var["attrs"].to_h[ax], to: val.to_s.strip,
                    erp: false, reason: OlistProductWriter::NOT_SENDABLE["variation_attrs"], variation: key, attr: "attrs", axis: ax }
        end
      end
      if params.key?("kit_components")
        comps = clean(params["kit_components"])
        list << { key: "kit_components", label: LABELS["kit_components"], from: product.kit_components, to: comps, erp: true } if comps != clean(product.kit_components)
      end
      Hash(params["variation_components"]).each do |key, comps|
        var = product.variations.find { |x| x["key"] == key } or next
        comps = clean(comps)
        next if comps == clean(var["components"])

        list << { key: "variation:#{key}:components", label: "Variação #{var['sku']} · componentes do kit", from: var["components"], to: comps,
                  erp: true, variation: key, attr: "components" }
      end
      if params.key?("photos")
        ids = Array(params["photos"]).map(&:to_i)
        current = product.assets.where(kind: "foto").order(:position, :id).pluck(:id)
        added = product.assets.where(kind: "foto", source_url: nil).pluck(:id) & ids
        if ids != current || added.any?
          list << { key: "images", label: LABELS["images"], from: current.size, to: ids.size, erp: false, reason: OlistProductWriter::NOT_SENDABLE["images"] }
        end
      end
      list
    end

    def item(field, label, from, to)
      sendable = OlistProductWriter.sendable?(field)
      { key: field, label: label, from: from, to: to, erp: sendable, reason: sendable ? nil : OlistProductWriter::NOT_SENDABLE[field] }
    end

    def apply!(product, params, changes)
      changes.each do |c|
        if FIELDS.include?(c[:key])
          product.public_send("#{c[:key]}=", c[:to])
        elsif c[:key] == "kit_components"
          product.kit_components = c[:to]
        elsif c[:variation]
          product.variations = product.variations.map do |v|
            next v unless v["key"] == c[:variation]

            v = v.dup
            c[:attr] == "attrs" ? v["attrs"] = v["attrs"].to_h.merge(c[:axis] => c[:to]) : v[c[:attr]] = c[:to]
            v
          end
        end
      end
      product.save!
      reorder_photos!(product, Array(params["photos"]).map(&:to_i)) if changes.any? { |c| c[:key] == "images" }
    end

    def reorder_photos!(product, ids)
      fotos = product.assets.where(kind: "foto")
      fotos.where.not(id: ids).delete_all
      ids.each_with_index { |id, i| fotos.where(id: id).update_all(position: i + 1) }
    end

    def send_to_erp(product, changes)
      sendable = changes.select { |c| c[:erp] }
      return { results: [], not_sent: changes.reject { |c| c[:erp] } } if sendable.empty?

      fields = sendable.filter_map { |c| c[:key] if FIELDS.include?(c[:key]) }
      variations = sendable.select { |c| c[:variation] && %w[sku gtin price].include?(c[:attr]) }.group_by { |c| c[:variation] }
                           .to_h { |key, list| [ erp_id_of(product, key), list.to_h { |c| [ c[:attr], c[:to] ] } ] }
      kits = {}
      kits[product.erp_id] = product.kit_components if sendable.any? { |c| c[:key] == "kit_components" }
      sendable.select { |c| c[:attr] == "components" }.each { |c| kits[erp_id_of(product, c[:variation])] = c[:to] }
      results = writer.call(product, fields: fields, variations: variations.compact, kits: kits)
      { results: results, not_sent: changes.reject { |c| c[:erp] } }
    end

    # Campos alterados ficam como "ajuste do Lunna", exceto o que o ERP aceitou agora (Lunna e ERP iguais de novo).
    def mark_overrides!(product, changes, before, erp)
      accepted = accepted_keys(changes, erp)
      ov = product.local_overrides.dup
      changes.each do |c|
        key = override_key(c)
        if accepted.include?(c[:key])
          ov.delete(key) unless key == "variations" && changes.any? { |o| override_key(o) == "variations" && !accepted.include?(o[:key]) }
          next
        end
        ov[key] ||= { "erp_value" => before[key], "at" => Time.current.iso8601, "user" => @user&.name }
      end
      product.update_columns(local_overrides: ov, updated_at: Time.current)
    end

    def accepted_keys(changes, erp)
      return [] unless erp

      ok = Array(erp[:results]).select { |r| r[:ok] }
      changes.select do |c|
        next false unless c[:erp]

        ok.any? do |r|
          (r[:what] == "produto" && Array(r[:fields]).include?(c[:key])) || (r[:what] == "kit" && %w[kit_components components].include?(c[:attr] || c[:key])) ||
            (r[:what].to_s.start_with?("variação") && c[:variation])
        end
      end.map { |c| c[:key] }
    end

    def override_key(c)
      return "variations" if c[:variation]
      return "images" if c[:key] == "images"

      c[:key]
    end

    def snapshot(product)
      FIELDS.to_h { |f| [ f, product.public_send(f) ] }.merge("variations" => product.variations.deep_dup, "kit_components" => product.kit_components.deep_dup,
                                                               "images" => nil)
    end

    def erp_id_of(product, key) = product.variations.find { |v| v["key"] == key }&.dig("erp_id")

    def writer = @writer ||= OlistProductWriter.new(@company, user: @user)

    def clean(list) = Array(list).filter_map { |c| c = c.to_h.stringify_keys; { "sku" => c["sku"].to_s.strip, "quantity" => c["quantity"].to_s.tr(",", ".").to_f.then { |q| q.positive? ? q : 1.0 } } if c["sku"].present? }

    def normalize(field, v)
      case field
      when "price", "weight_net", "weight_gross", "min_stock", "max_stock" then v.presence&.to_s&.tr(",", ".")&.to_f
      when "package_width", "package_height", "package_length", "preparation_days", "icms_origin" then v.presence&.to_i
      when "stock_control" then ActiveModel::Type::Boolean.new.cast(v) || false
      when "ncm", "cest" then v.to_s.gsub(/\D/, "").presence
      else v.to_s.strip.presence
      end
    end

    def same?(a, b)
      return a.to_f.round(4) == b.to_f.round(4) if a.is_a?(Numeric) || a.is_a?(BigDecimal) || b.is_a?(Numeric)

      a.to_s == b.to_s
    end
  end
end
