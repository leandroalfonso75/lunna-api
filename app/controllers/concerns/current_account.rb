# Resolve a conta do Mercado Livre das leituras do painel a partir de
# `?account_id=` — sempre dentro da empresa do usuário logado (conta de outra
# empresa ou inexistente → 404; sem o parâmetro → 422).
module CurrentAccount
  extend ActiveSupport::Concern

  included do
    before_action :set_current_account
  end

  private

  def set_current_account
    Current.account = Current.company.ml_accounts.find(params.require(:account_id))
  end
end
