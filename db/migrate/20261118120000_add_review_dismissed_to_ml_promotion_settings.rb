# "Ciente, nada a ser feito" em Promoções > Para revisar (pedido do usuário em 18/11/2026): o anúncio sai da guia e da
# contagem; volta sozinho quando sair de "Para revisar" e entrar de novo depois.
class AddReviewDismissedToMlPromotionSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_promotion_settings, :review_dismissed_at, :datetime
    add_reference :ml_promotion_settings, :review_dismissed_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
