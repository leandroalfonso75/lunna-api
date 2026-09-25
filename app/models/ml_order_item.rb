# Linha de um pedido (SPEC 5). PK composta (order_id, item_id); só acessada
# via MlOrder da conta (DECISOES §2) — nunca direto.
class MlOrderItem < ApplicationRecord
  self.primary_key = [ "order_id", "item_id" ]

  belongs_to :ml_order, foreign_key: "order_id", inverse_of: :ml_order_items
end
