# Visitas diárias de um anúncio (SPEC 5). PK composta (item_id, day).
class MlItemVisit < ApplicationRecord
  self.primary_key = [ "item_id", "day" ]

  belongs_to :ml_account
end
