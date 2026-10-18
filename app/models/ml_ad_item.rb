# Anúncio dentro de uma campanha de Product Ads. `metrics` guarda as janelas lidas
# ({ "7d" => {...}, "30d" => {...}, "90d" => {...} }).
class MlAdItem < ApplicationRecord
  self.primary_key = [ :ml_account_id, :item_id ]

  belongs_to :ml_account
end
