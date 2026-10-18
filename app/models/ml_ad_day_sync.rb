# Dia de publicidade já lido do Mercado Livre (por anúncio). Fechado = lido depois que o dia acabou.
class MlAdDaySync < ApplicationRecord
  belongs_to :ml_account

  def closed? = fetched_at.in_time_zone.to_date > date
end
