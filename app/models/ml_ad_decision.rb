# Decisão tomada na aba Análise de Ads (feito ou ignorado), com o "antes" guardado (ver Painel::AdsAnalysis).
class MlAdDecision < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true

  STATUSES = %w[feito ignorado].freeze
  validates :status, inclusion: { in: STATUSES }
end
