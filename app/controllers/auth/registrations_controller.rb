# POST /auth/sign_up {company_name, name, email, password} → 201
# {token, user, company, ml_accounts: []}
#
# Cria Company + User admin + Session numa única transação: uma falha em
# qualquer etapa (ex.: e-mail duplicado) não deixa empresa órfã pra trás.
module Auth
  class RegistrationsController < ApplicationController
    skip_before_action :authenticate!

    rate_limit to: 5, within: 1.hour,
      with: -> { render_errors([ "Muitas tentativas. Tente de novo em instantes." ], status: :too_many_requests) }

    def create
      company = nil
      user = nil
      token = nil

      ActiveRecord::Base.transaction do
        company = Company.create!(name: sign_up_params[:company_name])
        user = company.users.create!(
          name: sign_up_params[:name],
          email: sign_up_params[:email],
          password: sign_up_params[:password],
          role: "admin"
        )
        _session, token = Session.start!(user, request)
      end

      render json: {
        token: token,
        user: user_payload(user),
        company: company_payload(company),
        ml_accounts: []
      }, status: :created
    end

    private

    def sign_up_params
      params.permit(:company_name, :name, :email, :password)
    end
  end
end
