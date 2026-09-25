# POST /auth/sign_in {email, password} → 200 {token, user, company, ml_accounts}
# DELETE /auth/sign_out (logado) → 204, apaga a sessão atual
module Auth
  class SessionsController < ApplicationController
    skip_before_action :authenticate!, only: :create

    rate_limit to: 10, within: 3.minutes, only: :create,
      with: -> { render_errors([ "Muitas tentativas. Tente de novo em instantes." ], status: :too_many_requests) }

    def create
      user = User.authenticate_by(email: params[:email], password: params[:password])

      unless user
        return render_errors([ "E-mail ou senha inválidos." ], status: :unauthorized)
      end

      _session, token = Session.start!(user, request)

      render json: {
        token: token,
        user: user_payload(user),
        company: company_payload(user.company),
        ml_accounts: user.company.ml_accounts.order(:created_at).map { |account| ml_account_payload(account) }
      }, status: :ok
    end

    def destroy
      Current.session.destroy
      head :no_content
    end
  end
end
