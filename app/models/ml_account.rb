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
  has_many :ml_sync_runs
  has_many :item_metrics
  has_many :ai_plans

  encrypts :access_token, :refresh_token

  validates :seller_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
end
