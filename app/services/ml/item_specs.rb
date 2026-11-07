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

    def info
      @info ||= begin
        filled = Array(item["attributes"]).select { |a| a["value_id"].present? || a["value_name"].present? }.map { |a| a["id"] }.to_set
        relevant = Array(@client.category_attributes(item["category_id"])).reject { |a| excluded?(a) }
        missing = relevant.select { |a| (required?(a) || a["relevance"] == 1) && !filled.include?(a["id"]) }
        { item_id: @item_id, title: item["title"], category_id: item["category_id"],
          filled: Array(item["attributes"]).filter_map { |a| { id: a["id"], name: a["name"], value: a["value_name"] } if a["value_name"].present? },
          fields: missing.sort_by { |a| required?(a) ? 0 : 1 }.map { |a| field(a) } }
      end
    end

    # values: { "ATTR_ID" => { "value_id" => "...", "value_name" => "..." } } (vazios ficam de fora)
    def publish(values, user)
      fields = info[:fields].index_by { |f| f[:id] }
      attrs = values.to_h.filter_map do |id, v|
        v = v.to_h.stringify_keys
        next unless fields[id.to_s]
        if ActiveModel::Type::Boolean.new.cast(v["not_applicable"])
          next unless fields[id.to_s][:not_applicable]

          next { id: id.to_s, value_id: Ml::SpecRules::NOT_APPLICABLE, value_name: nil }
        end
        next if v["value_id"].blank? && v["value_name"].to_s.strip.blank?

        v["value_id"].present? ? { id: id.to_s, value_id: v["value_id"].to_s } : { id: id.to_s, value_name: v["value_name"].to_s.strip }
      end
      return Result.new(ok: false, published: 0, message: "Preencha ao menos um campo da ficha técnica.") if attrs.empty?

      edit = @account.ml_item_edits.create!(item_id: @item_id, user: user, kind: "ficha_tecnica", before: { missing: fields.keys }, after: { attributes: attrs })
      @client.update_item(@item_id, { attributes: attrs })
      edit.update!(ok: true)
      refresh_local(attrs.map { |a| a[:id] })
      Result.new(ok: true, published: attrs.size, message: "#{attrs.size} característica(s) publicada(s) no Mercado Livre.")
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(500))
      Result.new(ok: false, published: 0, message: "O Mercado Livre recusou a alteração: #{e.message.to_s.first(260)}")
    end

    private

    def field(a)
      tags = a["tags"] || {}
      { id: a["id"], name: a["name"], value_type: a["value_type"], required: required?(a), hint: a["hint"].presence || a["tooltip"].presence,
        values: Array(a["values"]).first(MAX_VALUES).map { |v| { id: v["id"], name: v["name"] } },
        free_text: !tags["fixed_values"] && a["value_type"] != "boolean",
        units: Array(a["allowed_units"]).map { |u| { id: u["id"], name: u["name"] } }, default_unit: a["default_unit"],
        max_length: a["value_max_length"], not_applicable: Ml::SpecRules.allows_not_applicable?(a) }
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
