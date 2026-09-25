# GET /api/me → {user, company, ml_accounts}
class MeController < ApplicationController
  def show
    render json: {
      user: user_payload(Current.user),
      company: company_payload(Current.company),
      ml_accounts: Current.company.ml_accounts.order(:created_at).map { |account| ml_account_payload(account) }
    }
  end
end
