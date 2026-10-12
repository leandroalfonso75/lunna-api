# Estoque do Full (Fulfillment do Mercado Livre) de um inventory_id, lido direto
# do ML (GET /inventories/{id}/stock/fulfillment) pela sincronização.
class MlFullStock < ApplicationRecord
  belongs_to :ml_account
end
