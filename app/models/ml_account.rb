class MlAccount < ApplicationRecord
  STATUSES = %w[active reauth_required].freeze

  belongs_to :company
  belongs_to :connected_by_user, class_name: "User", optional: true

  has_many :ml_items
  has_many :ml_item_visits
  has_many :ml_orders
  has_many :ml_claims, dependent: :delete_all
  has_many :ml_claim_replies, dependent: :delete_all
  has_many :ml_claim_contests, dependent: :delete_all
  has_many :ml_claim_actions, dependent: :delete_all
  has_many :finance_entries, dependent: :delete_all
  has_many :ml_item_edits, dependent: :delete_all

  validates :ads_roas_target, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 100 }, allow_nil: true

  # ROAS Objetivo do vendedor (Configurações › Ads); nil quando desligado.
  def ads_roas_goal = ads_roas_target_enabled && ads_roas_target.present? ? ads_roas_target.to_f : nil
  has_many :ml_questions, dependent: :delete_all
  has_many :ml_conversations, dependent: :delete_all
  has_many :ml_message_sends, dependent: :delete_all
  has_many :ml_question_answers, dependent: :delete_all
  has_many :abc_suggestion_acks, dependent: :delete_all
  has_many :mp_payments, dependent: :delete_all
  has_many :mp_release_lines, dependent: :delete_all
  has_many :ml_billing_charges, dependent: :delete_all
  has_many :ml_photo_jobs, dependent: :destroy
  has_many :ml_ad_campaigns
  has_many :ml_ad_items
  has_many :ml_ad_daily_metrics
  has_many :ml_ad_decisions, dependent: :delete_all
  has_many :ml_catalog_checks, dependent: :delete_all # antes das ações (chave estrangeira)
  has_many :ml_promotions, dependent: :delete_all
  has_many :ml_promotion_offers, dependent: :delete_all
  has_many :ml_promotion_settings, dependent: :delete_all
  has_many :ml_promotion_actions, dependent: :delete_all
  has_many :ml_promotion_runs, dependent: :delete_all
  has_many :ml_ad_item_dailies
  has_many :ml_ad_day_syncs
  has_many :ml_sync_runs
  has_many :item_metrics
  has_many :ai_plans

  encrypts :access_token, :refresh_token

  validates :seller_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
end
