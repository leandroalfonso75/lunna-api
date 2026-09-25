class User < ApplicationRecord
  ROLES = %w[admin member].freeze

  belongs_to :company
  has_many :sessions

  has_secure_password

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: 8 }, allow_nil: true

  def admin?
    role == "admin"
  end
end
