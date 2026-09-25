# GET /api/painel (SPEC 10.3) → cabeçalho, KPIs, gráfico, listas e alertas.
# `sync` e `generated_at` são sempre calculados na hora; o resto vem de
# Rails.cache, invalidado por rodada de sync, empresa (parâmetros mudam a
# Curva ABC) e dia corrente (janelas de período mudam à meia-noite).
class PainelController < ApplicationController
  include CurrentAccount

  def show
    account = Current.account
    company = Current.company
    last_run_id = account.ml_sync_runs.order(started_at: :desc).limit(1).pick(:id)
    cache_key = [ "painel", account.id, last_run_id, company.updated_at.to_i, Date.current ]

    snapshot = Rails.cache.fetch(cache_key) { build_snapshot(account) }

    render json: snapshot.merge(sync: Painel::SyncStatus.call(account), generated_at: Time.current)
  end

  private

  def build_snapshot(account)
    metrics = account.item_metrics
    daily = Painel::Daily.call(account)

    {
      account: { id: account.id, nickname: account.nickname, seller_id: account.seller_id },
      period: period_payload,
      summary: Painel::Summary.call(account),
      kpis: Painel::Kpis.call(metrics, daily[:daily]),
      daily: daily[:daily],
      daily_scale: daily[:daily_scale],
      top_sellers: Painel::TopSellers.call(metrics),
      alerts: Painel::Alerts.call(metrics).map { |alert| alert.except(:item_ids) },
      recent_sales: Painel::RecentSales.call(account)
    }
  end

  def period_payload
    periods = Painel::Periods.call
    { today: periods[:today], week: periods[:week], prev_week: periods[:prev_week],
      month: periods[:month], prev_month: periods[:prev_month] }
  end
end
