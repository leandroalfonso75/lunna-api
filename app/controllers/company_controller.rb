# GET /api/company (logado) / PATCH /api/company (admin) → {company}
class CompanyController < ApplicationController
  before_action :require_admin!, only: :update

  # Só estas mudam métricas já calculadas (A5) — trocar só a IA não precisa
  # recalcular nada (DECISOES §10).
  BUSINESS_PARAMS = %w[tax_pct min_margin_pct abc_cut_a abc_cut_b group_up_pct group_down_pct].freeze

  def show
    render json: { company: company_payload(Current.company) }
  end

  def update
    company = Current.company
    company.assign_attributes(company_params)
    apply_openrouter_api_key!(company)
    company.save!

    if (company.saved_changes.keys & BUSINESS_PARAMS).any?
      company.ml_accounts.find_each { |account| Painel::ItemMetrics.refresh(account) }
    end

    render json: { company: company_payload(company) }
  end

  private

  def company_params
    params.permit(:name, :tax_pct, :min_margin_pct, :abc_cut_a, :abc_cut_b, :group_up_pct, :group_down_pct, :fixed_expenses_pct, :max_margin_pct, :promo_routine_enabled,
                  :promo_routine_mode, :promo_allow_margin_drop, :promo_margin_drop_tolerance, :promo_include_catalog, :ai_model,
                  :promo_schedule_hour, :promo_margin_basis, :promo_price_target, :promo_allow_price_increase, :promo_allow_lightning,
                  promo_schedule_days: [])
  end

  # `openrouter_api_key` ausente ou vazio mantém a atual; `remove_openrouter_api_key: true` apaga.
  def apply_openrouter_api_key!(company)
    if ActiveModel::Type::Boolean.new.cast(params[:remove_openrouter_api_key])
      company.openrouter_api_key = nil
    elsif params[:openrouter_api_key].present?
      company.openrouter_api_key = params[:openrouter_api_key]
    end
  end
end
