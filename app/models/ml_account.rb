class MlAccount < ApplicationRecord
  STATUSES = %w[active reauth_required].freeze

  belongs_to :company
  belongs_to :connected_by_user, class_name: "User", optional: true

  has_many :ml_items
  has_many :ml_item_visits
  has_many :ml_orders
  has_many :ml_ad_campaigns
  has_many :ml_ad_items
  has_many :ml_ad_daily_metrics
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
