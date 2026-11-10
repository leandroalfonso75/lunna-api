class AddAdsRoasTargetToMlAccounts < ActiveRecord::Migration[8.1]
  def change
    # ROAS Objetivo do vendedor para o Ads, por conta (Configurações › Ads, pedido do usuário em 10/11/2026): ligado, a
    # Análise de Ads usa esse alvo além do equilíbrio do produto.
    add_column :ml_accounts, :ads_roas_target_enabled, :boolean, null: false, default: false
    add_column :ml_accounts, :ads_roas_target, :decimal, precision: 6, scale: 2
  end
end
