# Promoções: texto livre com regras específicas do anúncio (lido por quem opera e pela rotina).
class AddRulesNoteToMlPromotionSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_promotion_settings, :rules_note, :text
  end
end
