# "Já respondi no Mercado Livre" (pedido do usuário em 16/11/2026): a reclamação sai de "A atender" na hora, mesmo que o
# ML ainda aponte o vendedor; volta só se chegar mensagem nova do ML ou do comprador depois do clique.
class AddAttendedAtToMlClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_claims, :attended_at, :datetime
  end
end
