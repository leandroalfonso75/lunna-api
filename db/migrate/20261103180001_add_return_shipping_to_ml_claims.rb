class AddReturnShippingToMlClaims < ActiveRecord::Migration[8.1]
  # Custo do frete da devolução (/shipments/{id}/costs do envio de retorno): quanto ficou com o vendedor (receiver).
  def change
    add_column :ml_claims, :return_shipping, :jsonb
  end
end
