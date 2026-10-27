# Margem mínima/máxima de promoção de um anúncio. Com "aplicar ao SKU", os outros anúncios do mesmo SKU recebem os
# mesmos valores (e passam a seguir este).
module Painel
  module PromotionSettings
    FIELDS = %i[min_margin_pct max_margin_pct automation_enabled].freeze

    module_function

    # => [ settings gravadas ] ou levanta ActiveRecord::RecordInvalid
    def update(account, item_id, attrs, user)
      item = account.ml_items.find(item_id)
      apply = ActiveModel::Type::Boolean.new.cast(attrs[:apply_to_sku]) && item.sku.present?
      values = FIELDS.each_with_object({}) { |f, h| h[f] = blank_to_nil(attrs[f]) if attrs.key?(f) }
      values[:automation_enabled] = true if values.key?(:automation_enabled) && values[:automation_enabled].nil?

      targets = [ item.item_id ]
      targets += account.ml_items.where(sku: item.sku).where.not(item_id: item.item_id).pluck(:item_id) if apply

      MlPromotionSetting.transaction do
        targets.map do |id|
          setting = account.ml_promotion_settings.find_or_initialize_by(item_id: id)
          setting.assign_attributes(values.merge(sku: item.sku, apply_to_sku: apply || false, updated_by: user))
          setting.save!
          setting
        end
      end
    end

    def blank_to_nil(value) = value.to_s.strip.empty? ? nil : value
  end
end
