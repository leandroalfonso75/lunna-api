# Traduz o body de UM item do multiget (SPEC 3, endpoint 5) para as colunas
# de ml_items que essa chamada sozinha já preenche. Função pura — não faz
# HTTP, não grava nada; usada pela etapa 2 da sincronização.
module Ml
  class ItemAttributes
    def self.from(body, account)
      new(body, account).to_h
    end

    def initialize(body, account)
      @body = body
      @account = account
    end

    def to_h
      {
        item_id: @body["id"],
        ml_account_id: @account.id,
        seller_id: @account.seller_id,
        title: @body["title"],
        status: @body["status"],
        sub_status: @body["sub_status"] || [],
        price: @body["price"],
        original_price: @body["original_price"],
        available_quantity: @body["available_quantity"],
        sold_quantity: @body["sold_quantity"],
        listing_type_id: @body["listing_type_id"],
        category_id: @body["category_id"],
        logistic_type: logistic_type,
        free_shipping: !!shipping["free_shipping"],
        catalog_listing: !!@body["catalog_listing"],
        permalink: @body["permalink"],
        thumbnail: @body["thumbnail"],
        sku: sku,
        variations_count: variations.size,
        pictures_count: pictures.size,
        has_video: @body["video_id"].present?,
        brand: attribute_value("BRAND"),
        model: attribute_value("MODEL"),
        attrs_filled: attrs_filled,
        health: @body["health"],
        date_created: @body["date_created"],
        last_updated: @body["last_updated"],
        synced_at: Time.current
      }
    end

    private

    def shipping
      @body["shipping"] || {}
    end

    def logistic_type
      shipping["logistic_type"]
    end

    def variations
      @body["variations"] || []
    end

    def attributes
      @body["attributes"] || []
    end

    def pictures
      @body["pictures"] || []
    end

    # SPEC 3: seller_custom_field do item → atributo SELLER_SKU do item →
    # seller_custom_field ou SELLER_SKU da primeira variação.
    def sku
      @body["seller_custom_field"].presence ||
        attribute_value("SELLER_SKU").presence ||
        first_variation_sku
    end

    def first_variation_sku
      variation = variations.first
      return nil unless variation

      variation["seller_custom_field"].presence ||
        attribute_value_in(variation["attributes"], "SELLER_SKU")
    end

    def attribute_value(id)
      attribute_value_in(attributes, id)
    end

    def attribute_value_in(list, id)
      attribute = (list || []).find { |a| a["id"] == id }
      return nil unless attribute

      attribute["value_name"].presence || attribute.dig("values", 0, "name")
    end

    # Atributo preenchido: tem value_id, ou value_name não vazio, ou values
    # com itens (SPEC 3). Conta atributos do item, das variações
    # (attribute_combinations) e os próprios attributes de cada variação.
    def attrs_filled
      ids = filled_ids(attributes)

      variations.each do |variation|
        ids += filled_ids(variation["attribute_combinations"])
        ids += filled_ids(variation["attributes"])
      end

      ids.uniq
    end

    def filled_ids(list)
      (list || []).select { |attribute| filled?(attribute) }.map { |attribute| attribute["id"] }
    end

    def filled?(attribute)
      attribute["value_id"].present? ||
        attribute["value_name"].present? ||
        (attribute["values"].is_a?(Array) && attribute["values"].any?)
    end
  end
end
