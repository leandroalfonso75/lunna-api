# State de uso único do fluxo OAuth do Olist: grava company/user ao iniciar a
# autorização e é consumido (apagado) no callback.
class OlistOauthState < ApplicationRecord
  self.primary_key = "state"

  TTL = 1.hour

  belongs_to :company
  belongs_to :user

  scope :expired, -> { where("created_at < ?", TTL.ago) }
end
