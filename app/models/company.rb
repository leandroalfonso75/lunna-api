class Company < ApplicationRecord
  has_many :users
  has_many :ml_accounts

  validates :name, presence: true
  validates :tax_pct, :min_margin_pct,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :abc_cut_a, numericality: { greater_than: 0 }
  validates :abc_cut_b, numericality: { less_than_or_equal_to: 100 }
  validates :group_up_pct, numericality: { greater_than_or_equal_to: 0 }
  validates :group_down_pct, numericality: { less_than_or_equal_to: 0 }
  validate :abc_cut_a_below_abc_cut_b

  private

  def abc_cut_a_below_abc_cut_b
    return if abc_cut_a.blank? || abc_cut_b.blank?

    errors.add(:abc_cut_a, "deve ser menor que abc_cut_b") if abc_cut_a >= abc_cut_b
  end
end
