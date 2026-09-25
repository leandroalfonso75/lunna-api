class MlAccount < ApplicationRecord
  STATUSES = %w[active reauth_required].freeze

  belongs_to :company
  belongs_to :connected_by_user, class_name: "User", optional: true

  encrypts :access_token, :refresh_token

  validates :seller_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
end
