# Promoções: limites por valor (preço mínimo/máximo, R$) como alternativa à margem, e "aplicar às variações do produto".
class AddPriceLimitsToMlPromotionSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_promotion_settings, :limit_mode, :string, null: false, default: "margin" # margin | price
    add_column :ml_promotion_settings, :min_price, :decimal, precision: 12, scale: 2
    add_column :ml_promotion_settings, :max_price, :decimal, precision: 12, scale: 2
    add_column :ml_promotion_settings, :apply_to_variations, :boolean, null: false, default: false
  end
end
