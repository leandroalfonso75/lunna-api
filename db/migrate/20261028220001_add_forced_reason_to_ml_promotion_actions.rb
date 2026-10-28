class AddForcedReasonToMlPromotionActions < ActiveRecord::Migration[8.1]
  def change
    # "Aplicar mesmo assim": a regra do Lunna que a oferta feria quando o administrador aplicou
    add_column :ml_promotion_actions, :forced_reason, :string
  end
end
