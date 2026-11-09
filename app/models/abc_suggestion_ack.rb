# "Ciente" numa sugestão da Curva ABC (Vídeo, Tipo de anúncio, Qualidade): esconde a sugestão até `until_at`;
# depois disso, se ela ainda valer, volta a aparecer.
class AbcSuggestionAck < ApplicationRecord
  KINDS = { "aplicada" => 30.days, "aguardar" => 15.days }.freeze

  # Sugestões de preço (Preço e Frete) em maturação: depois de aplicar um preço sugerido ou de "Não aplicar nenhum preço
  # sugerido", nenhuma sugestão de preço por 15 dias (pedido do usuário em 09/11/2026).
  PRICE_KEY = "preço:*"
  PRICE_HOLD = 15.days
  PRICE_AREAS = [ "preço", "frete" ].freeze

  def self.hold_price!(account, item_id, kind:, user: nil)
    ack = account.abc_suggestion_acks.find_or_initialize_by(item_id: item_id, key: PRICE_KEY)
    ack.update!(kind: kind, until_at: PRICE_HOLD.from_now, user: user)
    ack
  end

  belongs_to :ml_account
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS.keys }

  scope :active, -> { where("until_at > ?", Time.current) }
end
