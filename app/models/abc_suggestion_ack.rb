# "Ciente" numa sugestão da Curva ABC (Vídeo, Tipo de anúncio, Qualidade): esconde a sugestão até `until_at`;
# depois disso, se ela ainda valer, volta a aparecer.
class AbcSuggestionAck < ApplicationRecord
  KINDS = { "aplicada" => 30.days, "aguardar" => 15.days }.freeze

  belongs_to :ml_account
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS.keys }

  scope :active, -> { where("until_at > ?", Time.current) }
end
