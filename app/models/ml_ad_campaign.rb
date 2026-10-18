# Campanha de Product Ads do Mercado Livre (seção Ads). Métricas ficam em ml_ad_daily_metrics.
class MlAdCampaign < ApplicationRecord
  self.primary_key = [ :ml_account_id, :campaign_id ]

  belongs_to :ml_account
end
