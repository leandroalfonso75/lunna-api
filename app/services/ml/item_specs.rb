# Curva ABC > "Alterar ficha técnica AGORA" (pedido do usuário em 07/11/2026): os campos da ficha técnica que faltam
# (obrigatórios e principais da categoria, as mesmas regras de Ml::Sync::Details) e a publicação no ML.
# Escrita no ML: só admin, com confirmação, registrada em ml_item_edits.
module Ml
  class ItemSpecs
    MAX_VALUES = 300
    Result = Struct.new(:ok, :message, :published, keyword_init: true)

    def self.info(client, account, item_id) = new(client, account, item_id).info
    def self.publish(client, account, item_id, values, user:) = new(client, account, item_id).publish(values, user)

    def initialize(client, account, item_id)
      @client = client
      @account = account
      @item_id = item_id
    end

    def item = @item ||= @client.item_full(@item_id)

    # Anúncio com variações (ex.: Preto 127V / Preto 220V; erro 400 "item.attributes.invalid" em 11/11/2026):
    # - o que já está nas combinações das variações (COLOR, VOLTAGE...) conta como preenchido e não volta a ser pedido;
    # - atributo de variação (tag variation_attribute: MAIN_COLOR, DETAILED_MODEL, GTIN...) vai em cada variação, não no
    #   anúncio; o mesmo valor para todas, menos o código universal (GTIN), que é um por variação.
    EACH_VARIATION = %w[GTIN].freeze

    def variations = Array(item["variations"])

    def info
      @info ||= begin
        lists = [ item["attributes"] ] + variations.flat_map { |v| [ v["attribute_combinations"], v["attributes"] ] }
        filled = lists.flat_map { |l| Array(l) }.select { |a| a["value_id"].present? || a["value_name"].present? }.map { |a| a["id"] }.to_set
        relevant = Array(@client.category_attributes(item["category_id"])).reject { |a| excluded?(a) }
        missing = relevant.select { |a| (required?(a) || a["relevance"] == 1) && !filled.include?(a["id"]) }
        { item_id: @item_id, title: item["title"], category_id: item["category_id"],
          variations: variations.map { |v| { id: v["id"], label: variation_label(v) } },
          filled: Array(item["attributes"]).filter_map { |a| { id: a["id"], name: a["name"], value: a["value_name"] } if a["value_name"].present? },
          fields: missing.sort_by { |a| required?(a) ? 0 : 1 }.map { |a| field(a) } }
      end
    end

    # values: { "ATTR_ID" => { "value_id" => "...", "value_name" => "..." } } (vazios ficam de fora). Campo de variação
    # com um valor por variação (GTIN): { "GTIN" => { "variations" => { "<id da variação>" => { "value_name" => "..." } } } }.
    def publish(values, user)
      fields = info[:fields].index_by { |f| f[:id] }
      item_attrs = []
      per_variation = Hash.new { |h, k| h[k] = [] }
      values.to_h.each do |id, v|
        v = v.to_h.stringify_keys
        f = fields[id.to_s]
        next unless f

        if f[:per_variation] == "each"
          v["variations"].to_h.each do |vid, vv|
            attr = attr_from(id.to_s, vv.to_h.stringify_keys, f)
            per_variation[vid.to_s] << attr if attr && variations.any? { |x| x["id"].to_s == vid.to_s }
          end
          next
        end
        attr = attr_from(id.to_s, v, f)
        next unless attr

        if f[:per_variation] == "same"
          variations.each { |x| per_variation[x["id"].to_s] << attr }
        else
          item_attrs << attr
        end
      end
      published = (item_attrs.map { |a| a[:id] } + per_variation.values.flatten.map { |a| a[:id] }).uniq
      return Result.new(ok: false, published: 0, message: "Preencha ao menos um campo da ficha técnica.") if published.empty?

      body = {}
      body[:attributes] = item_attrs if item_attrs.any?
      # variações: manda TODAS (a que fica de fora é apagada pelo ML), com os atributos que já tinham mais os novos
      if per_variation.any?
        body[:variations] = variations.map do |x|
          kept = Array(x["attributes"]).reject { |a| per_variation[x["id"].to_s].any? { |n| n[:id] == a["id"] } }
                                       .map { |a| a["value_id"].present? ? { id: a["id"], value_id: a["value_id"] } : { id: a["id"], value_name: a["value_name"] } }
          { id: x["id"], attributes: kept + per_variation[x["id"].to_s] }
        end
      end
      edit = @account.ml_item_edits.create!(item_id: @item_id, user: user, kind: "ficha_tecnica", before: { missing: fields.keys }, after: body)
      @client.update_item(@item_id, body)
      edit.update!(ok: true)
      refresh_local(published)
      Result.new(ok: true, published: published.size, message: "#{published.size} característica(s) publicada(s) no Mercado Livre.")
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(2000))
      Result.new(ok: false, published: 0, message: "O Mercado Livre recusou a alteração: #{self.class.ml_reason(e.message)}")
    end

    # Motivo legível do erro do ML: as mensagens de "cause" (ou "message"), sem o JSON cru.
    def self.ml_reason(text)
      json = text.to_s[/\{.*\z/m]
      data = json && (JSON.parse(json) rescue nil)
      return text.to_s.first(300) unless data.is_a?(Hash)

      msgs = Array(data["cause"]).filter_map { |c| c["message"].presence } + [ data["message"] ].compact
      msgs.uniq.join(" · ").presence || text.to_s.first(300)
    end

    private

    def attr_from(id, v, f)
      if ActiveModel::Type::Boolean.new.cast(v["not_applicable"])
        return nil unless f[:not_applicable]

        return { id: id, value_id: Ml::SpecRules::NOT_APPLICABLE, value_name: nil }
      end
      return nil if v["value_id"].blank? && v["value_name"].to_s.strip.blank?

      v["value_id"].present? ? { id: id, value_id: v["value_id"].to_s } : { id: id, value_name: v["value_name"].to_s.strip }
    end

    def variation_label(v)
      Array(v["attribute_combinations"]).filter_map { |a| a["value_name"].presence }.join(" · ").presence || v["id"].to_s
    end

    def field(a)
      tags = a["tags"] || {}
      per_variation = variations.any? && tags["variation_attribute"] ? (EACH_VARIATION.include?(a["id"]) ? "each" : "same") : nil
      { id: a["id"], name: a["name"], value_type: a["value_type"], required: required?(a), hint: a["hint"].presence || a["tooltip"].presence,
        per_variation: per_variation,
        values: Array(a["values"]).first(MAX_VALUES).map { |v| { id: v["id"], name: v["name"] } },
        free_text: !tags["fixed_values"] && a["value_type"] != "boolean",
        units: Array(a["allowed_units"]).map { |u| { id: u["id"], name: u["name"] } }, default_unit: a["default_unit"],
        max_length: a["value_max_length"], not_applicable: Ml::SpecRules.allows_not_applicable?(a), multivalued: !!tags["multivalued"] }
    end

    def refresh_local(ids)
      row = @account.ml_items.find_by(item_id: @item_id)
      return unless row

      names = info[:fields].select { |f| ids.include?(f[:id]) }.map { |f| f[:name] }
      row.update_columns(attrs_filled: (Array(row.attrs_filled) + ids).uniq,
                         attrs_missing_required: Array(row.attrs_missing_required) - names,
                         attrs_missing_main: Array(row.attrs_missing_main) - names)
    end

    def excluded?(a) = Ml::SpecRules.excluded?(a)
    def required?(a) = Ml::SpecRules.required?(a)
  end
end
