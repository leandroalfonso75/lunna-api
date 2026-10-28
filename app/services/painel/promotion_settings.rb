# Limites de promoção de um anúncio: por margem (mínima/máxima, %) ou por valor (preço mínimo/máximo, R$) — um ou
# outro (limit_mode). Com "aplicar ao SKU", os outros anúncios do mesmo SKU recebem os mesmos valores; com "aplicar às
# variações", também os anúncios das outras variações do produto (mesmo produto pai no Olist).
module Painel
  module PromotionSettings
    MODES = %w[margin price].freeze
    FIELDS = %i[min_margin_pct max_margin_pct min_price max_price automation_enabled rules_note].freeze

    module_function

    # => [ settings gravadas ] ou levanta ActiveRecord::RecordInvalid
    def update(account, item_id, attrs, user)
      item = account.ml_items.find(item_id)
      bool = ActiveModel::Type::Boolean.new
      apply_sku = bool.cast(attrs[:apply_to_sku]) && item.sku.present?
      apply_variations = bool.cast(attrs[:apply_to_variations]) || false
      values = FIELDS.each_with_object({}) { |f, h| h[f] = blank_to_nil(attrs[f]) if attrs.key?(f) }
      values[:automation_enabled] = true if values.key?(:automation_enabled) && values[:automation_enabled].nil?
      values[:rules_note] = values[:rules_note].to_s.strip.first(2000).presence if values.key?(:rules_note)
      mode = MODES.include?(attrs[:limit_mode].to_s) ? attrs[:limit_mode].to_s : "margin"
      # um desabilita o outro: no modo valor a margem do anúncio é apagada, e vice-versa
      values.merge!(mode == "price" ? { min_margin_pct: nil, max_margin_pct: nil } : { min_price: nil, max_price: nil })

      targets = [ item.item_id ]
      targets += account.ml_items.where(sku: item.sku).where.not(item_id: item.item_id).pluck(:item_id) if apply_sku
      targets += variation_item_ids(account, item) if apply_variations

      MlPromotionSetting.transaction do
        targets.uniq.map do |id|
          setting = account.ml_promotion_settings.find_or_initialize_by(item_id: id)
          setting.assign_attributes(values.merge(sku: item.sku, limit_mode: mode, apply_to_sku: apply_sku || false,
                                                 apply_to_variations: apply_variations, updated_by: user))
          setting.save!
          setting
        end
      end
    end

    # Anúncios (ativos ou pausados) das outras variações do mesmo produto: SKUs com o mesmo produto pai no Olist.
    def variation_item_ids(account, item)
      return [] if item.sku.blank?

      company = account.company
      parent = OlistProduct.where(company_id: company.id, sku: item.sku).where.not(parent_olist_id: nil).pick(:parent_olist_id)
      return [] if parent.nil?

      skus = OlistProduct.where(company_id: company.id, parent_olist_id: parent).where.not(sku: [ nil, "", item.sku ]).pluck(:sku)
      account.ml_items.where(sku: skus, status: %w[active paused]).pluck(:item_id)
    end

    def blank_to_nil(value) = value.to_s.strip.empty? ? nil : value
  end
end
