class AddAdsCostDaysToCompanies < ActiveRecord::Migration[8.1]
  def change
    # Base do custo de Ads por unidade mostrado em Anúncios e usado em Promoções: últimos 7, 15 ou 30 dias fechados
    add_column :companies, :ads_cost_days, :integer, default: 15, null: false
  end
end
