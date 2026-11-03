class AddPeriodsToMlPromotionActions < ActiveRecord::Migration[8.1]
  def change
    # Período de cada promoção (antes e depois) e quando a mudança passa a valer: nil = na hora ("Em vigor");
    # data futura = programada (entra quando a atual acabar ou quando a nova começar).
    add_column :ml_promotion_actions, :from_start, :datetime
    add_column :ml_promotion_actions, :from_finish, :datetime
    add_column :ml_promotion_actions, :to_start, :datetime
    add_column :ml_promotion_actions, :to_finish, :datetime
    add_column :ml_promotion_actions, :effective_at, :datetime
  end
end
