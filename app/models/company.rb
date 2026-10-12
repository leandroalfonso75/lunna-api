class Company < ApplicationRecord
  # DECISOES §10 — id OpenRouter no formato "fornecedor/modelo" (sem espaço
  # nem barra no fornecedor; sem espaço no modelo).
  AI_MODEL_FORMAT = %r{\A[^\s/]+/\S+\z}

  has_many :users
  has_many :ml_accounts
  has_many :ml_costs
  has_many :radar_collections

  encrypts :openrouter_api_key

  normalizes :ai_model, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true
  validates :tax_pct, :min_margin_pct,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :abc_cut_a, numericality: { greater_than: 0 }
  validates :abc_cut_b, numericality: { less_than_or_equal_to: 100 }
  validates :group_up_pct, numericality: { greater_than_or_equal_to: 0 }
  validates :group_down_pct, numericality: { less_than_or_equal_to: 0 }
  validates :ai_model, format: { with: AI_MODEL_FORMAT }, length: { maximum: 120 }, allow_nil: true
  validate :abc_cut_a_below_abc_cut_b

  def ai_configured? = openrouter_api_key.present? && ai_model.present?

  def ai_key_hint
    return nil if openrouter_api_key.blank?

    "…#{openrouter_api_key.last(4)}"
  end

  private

  def abc_cut_a_below_abc_cut_b
    return if abc_cut_a.blank? || abc_cut_b.blank?

    errors.add(:abc_cut_a, "deve ser menor que abc_cut_b") if abc_cut_a >= abc_cut_b
  end
end
