# Plano de ação com IA por anúncio (SPEC 9, DECISOES §10), assíncrono e por
# polling: POST enfileira `Ai::ActionPlanJob` (202), GET lê o estado/texto
# parcial (o front repete até `done`/`error`), DELETE cancela. Anúncio de outra
# conta/empresa → 404 (escopo por `Current.account`).
class AiPlansController < ApplicationController
  include CurrentAccount

  rate_limit to: 10, within: 1.minute, only: :create,
    by: -> { Current.company&.id || request.remote_ip },
    with: -> { render_errors([ "Muitas tentativas. Tente de novo em instantes." ], status: :too_many_requests) }

  before_action :set_item

  def show
    render json: { ai_plan: plan && ai_plan_payload(plan) }
  end

  def create
    return render_errors([ Ai::ActionPlan::CONFIG_ERROR ], status: :unprocessable_content) unless Current.company.ai_configured?

    record = plan || Current.account.ai_plans.new(item_id: params[:id])
    if record.persisted? && record.active? && !record.stale?
      return render_errors([ "O plano deste anúncio já está sendo gerado." ], status: :conflict)
    end

    record.update!(status: "pending", text: "", error: nil)
    Ai::ActionPlanJob.perform_later(record.id)
    render json: { ai_plan: ai_plan_payload(record) }, status: :accepted
  end

  def destroy
    plan.update!(status: "cancelled") if plan&.active?
    head :no_content
  end

  private

  def set_item
    Current.account.item_metrics.find_by!(item_id: params[:id])
  end

  def plan
    @plan ||= Current.account.ai_plans.find_by(item_id: params[:id])
  end
end
