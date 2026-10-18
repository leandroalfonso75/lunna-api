# Seção Ads: id do anunciante (evita uma consulta a cada leitura) e carimbo da leitura rápida dos dias recentes.
class AddAdsSyncColumnsToMlAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_accounts, :ads_advertiser_id, :bigint
    add_column :ml_accounts, :ads_recent_synced_at, :datetime
  end
end
