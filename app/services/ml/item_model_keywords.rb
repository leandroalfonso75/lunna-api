# Curva ABC > "Alterar modelo AGORA" (pedido do usuário em 14/11/2026): o campo Modelo (MODEL) da ficha técnica aceita até
# 110 caracteres no Mercado Livre e entra na busca. Em vez do modelo do produto, vai uma sequência de palavras-chave (as
# mais buscadas para a categoria/produto no ML e no Google); o modelo de verdade vai em "Modelo detalhado" (DETAILED_MODEL).
# Lê o anúncio, a categoria e as tendências de busca do ML (`/trends/MLB/{categoria}`); publica com confirmação (admin),
# registrado em ml_item_edits (kind "modelo"). DETAILED_MODEL é atributo de variação: com variações, vai em cada uma.
module Ml
  class ItemModelKeywords
    Result = Struct.new(:ok, :message, :model, :detailed_model, keyword_init: true)
    DEFAULT_MAX = 110

    def self.info(client, account, item_id) = new(client, account, item_id).info
    def self.publish(client, account, item_id, model:, detailed_model:, user:) = new(client, account, item_id).publish(model, detailed_model, user)

    def initialize(client, account, item_id)
      @client = client
      @account = account
      @item_id = item_id
    end

    def item = @item ||= @client.item_full(@item_id)
    def variations = Array(item["variations"])

    def info
      @info ||= begin
        cat = Array(@client.category_attributes(item["category_id"]))
        model_def = cat.find { |a| a["id"] == "MODEL" } || {}
        detailed_def = cat.find { |a| a["id"] == "DETAILED_MODEL" }
        tags = detailed_def&.dig("tags")
        tags = tags.is_a?(Hash) ? tags.select { |_, v| v }.keys : Array(tags) # o ML manda {"variation_attribute": true}
        detailed_per_variation = variations.any? && tags.include?("variation_attribute")
        rule = if item["catalog_listing"]
          { editable: false, reason: "Anúncio de catálogo: a ficha técnica é a do produto do catálogo e o Mercado Livre não deixa trocar." }
        else
          { editable: true }
        end
        { item_id: @item_id, title: item["title"], category_id: item["category_id"],
          model: attr_value(Array(item["attributes"]), "MODEL"),
          detailed_model: attr_value(Array(item["attributes"]) + variations.flat_map { |v| Array(v["attributes"]) }, "DETAILED_MODEL"),
          detailed_available: detailed_def.present?, detailed_per_variation: !!detailed_per_variation,
          max_length: [ (model_def["value_max_length"].presence || DEFAULT_MAX).to_i, DEFAULT_MAX ].min.clamp(1, DEFAULT_MAX), # o ML aceita até 110 no Modelo
          brand: attr_value(Array(item["attributes"]), "BRAND"),
          attributes: Array(item["attributes"]).filter_map { |a| "#{a['name']}: #{a['value_name']}" if a["value_name"].present? }.first(40),
          trends: trends(item["category_id"]),
          **rule }
      end
    end

    def publish(model, detailed, user)
      model = model.to_s.squish
      detailed = detailed.to_s.squish
      data = info
      return Result.new(ok: false, message: data[:reason]) unless data[:editable]
      return Result.new(ok: false, message: "Escreva o novo Modelo.") if model.blank?
      return Result.new(ok: false, message: "O Modelo pode ter no máximo #{data[:max_length]} caracteres (tem #{model.length}).") if model.length > data[:max_length]
      return Result.new(ok: false, message: "O Modelo detalhado pode ter no máximo 255 caracteres.") if detailed.length > 255

      body = { attributes: [ { id: "MODEL", value_name: model } ] }
      if detailed.present? && data[:detailed_available]
        if data[:detailed_per_variation]
          # variações: manda TODAS (a que fica de fora é apagada pelo ML), com os atributos que já tinham
          body[:variations] = variations.map do |x|
            kept = Array(x["attributes"]).reject { |a| a["id"] == "DETAILED_MODEL" }
                                         .map { |a| a["value_id"].present? ? { id: a["id"], value_id: a["value_id"] } : { id: a["id"], value_name: a["value_name"] } }
            { id: x["id"], attributes: kept + [ { id: "DETAILED_MODEL", value_name: detailed } ] }
          end
        else
          body[:attributes] << { id: "DETAILED_MODEL", value_name: detailed }
        end
      end
      edit = @account.ml_item_edits.create!(item_id: @item_id, user: user, kind: "modelo",
                                            before: { model: data[:model], detailed_model: data[:detailed_model] }, after: body)
      @client.update_item(@item_id, body)
      edit.update!(ok: true)
      @account.ml_items.where(item_id: @item_id).update_all(model: model)
      msg = "Modelo alterado no Mercado Livre: \"#{model}\"."
      msg += " Modelo detalhado: \"#{detailed}\"." if detailed.present? && data[:detailed_available]
      Result.new(ok: true, model: model, detailed_model: detailed.presence, message: msg)
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(2000))
      Result.new(ok: false, message: "O Mercado Livre recusou a alteração: #{Ml::ItemSpecs.ml_reason(e.message)}")
    end

    private

    def attr_value(list, id) = list.find { |a| a["id"] == id && a["value_name"].present? }&.dig("value_name")

    # Palavras mais buscadas da categoria no ML (as primeiras são as que mais crescem/são mais buscadas).
    def trends(category_id)
      return [] if category_id.blank?

      Array(@client.trends(category_id)).filter_map { |t| t["keyword"].to_s.squish.presence }.uniq.first(30)
    rescue Ml::Client::Error
      []
    end
  end
end
