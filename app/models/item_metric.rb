# Métricas por anúncio (docs/METRICS.md), recalculadas inteiras por
# Painel::ItemMetrics.refresh a cada sincronização e a cada PATCH /api/company.
# Contrato compartilhado com a Curva ABC (A5) — não mude nomes de coluna.
class ItemMetric < ApplicationRecord
  self.primary_key = "item_id"

  belongs_to :ml_account
end
