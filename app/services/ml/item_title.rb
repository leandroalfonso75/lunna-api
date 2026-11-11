# Curva ABC > "Alterar título AGORA" (pedido do usuário em 07/11/2026): lê o estado do anúncio no ML, confere se dá para
# trocar o título (Ml::TitleRule, com as vendas atuais de todos os anúncios do mesmo user product) e publica.
# Escrita no ML: só admin, com confirmação, registrada em ml_item_edits.
module Ml
  class ItemTitle
    Result = Struct.new(:ok, :message, :title, keyword_init: true)

    def self.info(client, account, item_id) = new(client, account, item_id).info
    def self.publish(client, account, item_id, text, user:) = new(client, account, item_id).publish(text, user)

    def initialize(client, account, item_id)
      @client = client
      @account = account
      @item_id = item_id
    end

    def info
      @info ||= begin
        item = @client.item_full(@item_id)
        up = item["user_product_id"]
        sold = item["sold_quantity"].to_i
        if up.present?
          ids = (Array(@client.items_by_user_product(@account.seller_id, up)) - [ @item_id ]).first(20)
          sold += ids.sum { |id| @client.item_full(id)["sold_quantity"].to_i } # um a um: o multiget às vezes responde 403
        end
        mode = item["family_name"].present? || up.present? ? "family_name" : "title"
        rule = if item["catalog_listing"]
          { editable: false, reason: "Anúncio de catálogo: o título é o do produto do catálogo e o Mercado Livre não deixa trocar." }
        elsif sold.positive?
          { editable: false, reason: "O anúncio já tem #{sold} venda(s): o Mercado Livre só deixa trocar o título de anúncio sem vendas." }
        else
          { editable: true }
        end
        { item_id: @item_id, title: item["title"], family_name: item["family_name"], mode: mode, sold: sold,
          max_length: max_length(item["category_id"]), category_id: item["category_id"], brand: attr(item, "BRAND"), model: attr(item, "MODEL"),
          attributes: Array(item["attributes"]).filter_map { |a| "#{a['name']}: #{a['value_name']}" if a["value_name"].present? }.first(40),
          **rule }
      end
    end

    def publish(text, user)
      text = text.to_s.squish
      data = info
      return Result.new(ok: false, message: data[:reason]) unless data[:editable]
      return Result.new(ok: false, message: "Escreva o novo título.") if text.blank?
      return Result.new(ok: false, message: "O título pode ter no máximo #{data[:max_length]} caracteres (tem #{text.length}).") if text.length > data[:max_length]

      field = data[:mode] == "family_name" ? :family_name : :title
      before = { title: data[:title], family_name: data[:family_name] }
      edit = @account.ml_item_edits.create!(item_id: @item_id, user: user, kind: "titulo", before: before, after: { field => text })
      @client.update_item(@item_id, { field => text })
      fresh = (@client.item_full(@item_id) rescue {})
      new_title = fresh["title"].presence || text
      edit.update!(ok: true, after: { field => text, title: new_title })
      @account.ml_items.where(item_id: @item_id).update_all(title: new_title, family_name: fresh["family_name"] || (field == :family_name ? text : nil))
      @account.item_metrics.where(item_id: @item_id).update_all(title: new_title)
      Result.new(ok: true, title: new_title, message: "Título alterado no Mercado Livre: \"#{new_title}\".")
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(500))
      Result.new(ok: false, message: "O Mercado Livre recusou a alteração: #{e.message.to_s.first(220)}")
    end

    private

    def max_length(category_id)
      limit = (@client.category(category_id).dig("settings", "max_title_length") rescue nil).to_i
      limit.positive? ? [ limit, Ml::TitleRule::MAX_LENGTH ].min : Ml::TitleRule::MAX_LENGTH
    end

    def attr(item, id) = Array(item["attributes"]).find { |a| a["id"] == id }&.dig("value_name")
  end
end
