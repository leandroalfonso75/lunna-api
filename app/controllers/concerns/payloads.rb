# Monta à mão os hashes de resposta compartilhados entre controllers.
module Payloads
  extend ActiveSupport::Concern

  private

  def user_payload(user)
    { id: user.id, name: user.name, email: user.email, role: user.role }
  end

  def company_payload(company)
    {
      id: company.id,
      name: company.name,
      tax_pct: company.tax_pct.to_f,
      min_margin_pct: company.min_margin_pct.to_f,
      abc_cut_a: company.abc_cut_a.to_f,
      abc_cut_b: company.abc_cut_b.to_f,
      group_up_pct: company.group_up_pct.to_f,
      group_down_pct: company.group_down_pct.to_f
    }
  end

  def ml_account_payload(account)
    {
      id: account.id,
      seller_id: account.seller_id,
      nickname: account.nickname,
      status: account.status,
      last_error: account.last_error,
      connected_at: account.created_at,
      last_sync: last_sync_payload(account)
    }
  end

  # Preenchido por um bloco posterior a partir de ml_sync_runs.
  def last_sync_payload(_account)
    nil
  end
end
