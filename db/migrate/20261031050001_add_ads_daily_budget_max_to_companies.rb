class AddAdsDailyBudgetMaxToCompanies < ActiveRecord::Migration[8.1]
  def change
    # Limite máximo de investimento diário em Ads que as sugestões de estrutura de campanhas respeitam (null = não informado)
    add_column :companies, :ads_daily_budget_max, :decimal, precision: 12, scale: 2
  end
end
