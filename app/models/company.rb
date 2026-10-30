class Company < ApplicationRecord
  # DECISOES §10 — id OpenRouter no formato "fornecedor/modelo" (sem espaço
  # nem barra no fornecedor; sem espaço no modelo).
  AI_MODEL_FORMAT = %r{\A[^\s/]+/\S+\z}

  has_many :users
  has_many :ml_accounts
  has_many :ml_costs
  has_many :radar_collections
  has_many :radar_searches
  has_one :olist_connection
  has_many :olist_products
  has_many :olist_sync_runs
  has_many :olist_changes
  has_many :olist_stock_movements

  encrypts :openrouter_api_key

  normalizes :ai_model, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true
  validates :tax_pct, :min_margin_pct,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :abc_cut_a, numericality: { greater_than: 0 }
  validates :abc_cut_b, numericality: { less_than_or_equal_to: 100 }
  validates :group_up_pct, numericality: { greater_than_or_equal_to: 0 }
  validates :group_down_pct, numericality: { less_than_or_equal_to: 0 }
  validates :fixed_expenses_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :ai_model, format: { with: AI_MODEL_FORMAT }, length: { maximum: 120 }, allow_nil: true
  validates :max_margin_pct, numericality: { greater_than: -100, less_than: 100 }, allow_nil: true
  validates :promo_routine_mode, inclusion: { in: %w[simulation apply] }
  validates :promo_schedule_hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
  validates :promo_margin_basis, inclusion: { in: %w[after_ads before_ads] }
  validates :promo_price_target, inclusion: { in: %w[min max] }
  validate :promo_schedule_days_valid

  # Dias da semana da rotina de Promoções (0 = domingo … 6 = sábado); vazio = nunca roda.
  def promo_schedule_days_valid
    days = promo_schedule_days
    return if days.is_a?(Array) && days.all? { |d| d.is_a?(Integer) && d.between?(0, 6) } && days.uniq.size == days.size

    errors.add(:promo_schedule_days, "deve ser uma lista de dias da semana (0 a 6)")
  end

  # A rotina deve rodar agora (hora cheia, no horário de Brasília)?
  def promo_due?(now = Time.current.in_time_zone("America/Sao_Paulo"))
    promo_routine_enabled && now.hour == promo_schedule_hour && promo_schedule_days.include?(now.wday)
  end
  validate :max_margin_above_min
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

  def max_margin_above_min
    return if max_margin_pct.nil? || min_margin_pct.nil? || max_margin_pct >= min_margin_pct

    errors.add(:max_margin_pct, "precisa ser maior ou igual à margem mínima")
  end
end
