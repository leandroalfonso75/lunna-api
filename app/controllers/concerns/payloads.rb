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
      max_margin_pct: company.max_margin_pct&.to_f,
      promo_routine_enabled: company.promo_routine_enabled,
      promo_routine_mode: company.promo_routine_mode,
      promo_allow_margin_drop: company.promo_allow_margin_drop,
      promo_margin_drop_tolerance: company.promo_margin_drop_tolerance&.to_f,
      promo_include_catalog: company.promo_include_catalog,
      ads_cost_days: company.ads_cost_days,
      ads_daily_budget_max: company.ads_daily_budget_max&.to_f,
      promo_schedule_hour: company.promo_schedule_hour,
      promo_schedule_days: company.promo_schedule_days,
      promo_margin_basis: company.promo_margin_basis,
      promo_price_target: company.promo_price_target,
      promo_allow_price_increase: company.promo_allow_price_increase,
      promo_allow_lightning: company.promo_allow_lightning,
      abc_cut_a: company.abc_cut_a.to_f,
      abc_cut_b: company.abc_cut_b.to_f,
      group_up_pct: company.group_up_pct.to_f,
      group_down_pct: company.group_down_pct.to_f,
      fixed_expenses_pct: company.fixed_expenses_pct.to_f,
      ai_model: company.ai_model,
      ai_configured: company.ai_configured?,
      ai_key_hint: company.ai_key_hint
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

  def last_sync_payload(account)
    sync_run_payload(account.ml_sync_runs.order(started_at: :desc).first)
  end

  # Plano parado (worker caiu) sai como erro em vez de ficar "gerando" pra sempre.
  def ai_plan_payload(plan)
    stale = plan.stale?
    {
      id: plan.id,
      status: stale ? "error" : plan.status,
      text: plan.text,
      error: stale ? AiPlan::STALE_ERROR : plan.error,
      updated_at: plan.updated_at
    }
  end

  def sync_run_payload(run)
    return nil unless run

    {
      id: run.id,
      started_at: run.started_at,
      finished_at: run.finished_at,
      ok: run.ok,
      items: run.items,
      orders: run.orders,
      detail: run.detail
    }
  end
end
