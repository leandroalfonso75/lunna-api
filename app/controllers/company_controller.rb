# GET /api/company (logado) / PATCH /api/company (admin) → {company}
class CompanyController < ApplicationController
  before_action :require_admin!, only: :update

  def show
    render json: { company: company_payload(Current.company) }
  end

  def update
    company = Current.company
    company.update!(company_params)
    company.ml_accounts.find_each { |account| Painel::ItemMetrics.refresh(account) }
    render json: { company: company_payload(company) }
  end

  private

  def company_params
    params.permit(:name, :tax_pct, :min_margin_pct, :abc_cut_a, :abc_cut_b, :group_up_pct, :group_down_pct)
  end
end
