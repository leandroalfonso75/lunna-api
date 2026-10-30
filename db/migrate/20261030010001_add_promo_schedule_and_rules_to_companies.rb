class AddPromoScheduleAndRulesToCompanies < ActiveRecord::Migration[8.1]
  def change
    # Promoções: horário (hora cheia, 0 a 23) e dias da semana (0 = domingo … 6 = sábado) da rotina automática
    add_column :companies, :promo_schedule_hour, :integer, default: 3, null: false
    add_column :companies, :promo_schedule_days, :jsonb, default: [ 0, 1, 2, 3, 4, 5, 6 ], null: false
    # qual lucro vale para a margem mínima/máxima (after_ads | before_ads), o alvo do preço (min | max),
    # se pode subir o preço final para entrar em outra promoção e se a oferta relâmpago está autorizada
    add_column :companies, :promo_margin_basis, :string, default: "after_ads", null: false
    add_column :companies, :promo_price_target, :string, default: "min", null: false
    add_column :companies, :promo_allow_price_increase, :boolean, default: false, null: false
    add_column :companies, :promo_allow_lightning, :boolean, default: false, null: false
  end
end
