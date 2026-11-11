# Decisão tomada na aba Análise de Ads (feito ou ignorado), com o "antes" guardado (ver Painel::AdsAnalysis).
# Feito: vai para o Histórico de Ações e é revisado em REVIEW_DAYS (no 8º dia); "Aguardar mais 7 dias" adia a revisão,
# "Arquivar" tira do histórico. Ignorado: a sugestão sai da Análise por IGNORE_DAYS e só volta se o problema seguir.
class MlAdDecision < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true

  STATUSES = %w[feito ignorado].freeze
  REVIEW_DAYS = 7
  IGNORE_DAYS = 15
  validates :status, inclusion: { in: STATUSES }

  before_create { self.review_at ||= decided_at + REVIEW_DAYS.days if status == "feito" }

  scope :in_history, -> { where(status: "feito", archived_at: nil) }
  scope :ignoring, -> { where(status: "ignorado").where("decided_at > ?", IGNORE_DAYS.days.ago) }

  def due? = review_at.present? && review_at <= Time.current

  # Sinais tratados por esta decisão (o original e os feitos depois, na revisão): não voltam à fila enquanto ela está no histórico.
  def handled_signals = [ signal ] + Array(follow_ups).filter_map { |f| f["signal"] if f["type"] == "feito" }

  def add_follow_up!(entry)
    update!(follow_ups: Array(follow_ups) + [ entry.stringify_keys.merge("at" => Time.current.iso8601) ], review_at: Time.current + REVIEW_DAYS.days)
  end
end
