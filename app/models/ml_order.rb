# Pedido do Mercado Livre (SPEC 5). PK é o order_id do próprio ML.
class MlOrder < ApplicationRecord
  self.primary_key = "order_id"

  belongs_to :ml_account
  has_many :ml_order_items, foreign_key: "order_id", inverse_of: :ml_order
end
