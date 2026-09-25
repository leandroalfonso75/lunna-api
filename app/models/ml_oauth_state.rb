# State de uso único do fluxo OAuth do ML (DECISOES §5): grava company/user
# no início da autorização, consumido (apagado) no callback.
class MlOauthState < ApplicationRecord
  self.primary_key = "state"

  TTL = 1.hour

  belongs_to :company
  belongs_to :user

  scope :expired, -> { where("created_at < ?", TTL.ago) }
end
