# Proteção da sincronização (28/11/2026): conta marcada "autorizar de novo" ainda tenta renovar sozinha algumas vezes
# antes de exigir o usuário (em 27/11 uma falha passageira parou a sincronização por 20 horas).
class AddAuthRetryToMlAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_accounts, :auth_retry_count, :integer, null: false, default: 0
    add_column :ml_accounts, :auth_retry_at, :datetime
  end
end
