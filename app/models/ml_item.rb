# Anúncio do Mercado Livre (SPEC 5). PK é o item_id do próprio ML (ex.:
# "MLB1000000001"), gravado via Ml::Sync::Steps::Items com upsert_all.
class MlItem < ApplicationRecord
  self.primary_key = "item_id"

  belongs_to :ml_account
end
