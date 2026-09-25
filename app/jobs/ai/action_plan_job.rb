# Gera o plano de ação com IA fora do request (DECISOES §10): a resposta da
# OpenRouter chega em streaming, o texto parcial é gravado em `ai_plans` a cada
# ~1,5 s e o front consulta por polling — nenhuma conexão HTTP longa com o
# navegador, então proxy/timeout não derrubam a geração.
module Ai
  class ActionPlanJob < ApplicationJob
    SAVE_EVERY = 1.5.seconds

    class Cancelled < StandardError; end

    def perform(plan_id)
      plan = AiPlan.find_by(id: plan_id)
      return unless plan&.status == "pending"

      plan.update!(status: "running")
      text = +""
      saved_at = Time.current

      detail, row, context = Abc::Report.item_for_prompt(plan.ml_account, plan.item_id)
      prompt = Ai::ActionPlanPrompt.call(detail, row, context)

      Ai::ActionPlan.stream(plan.ml_account.company, prompt) do |chunk|
        text << chunk
        next if Time.current - saved_at < SAVE_EVERY

        raise Cancelled if plan.reload.status == "cancelled"

        plan.update_columns(text: text, updated_at: Time.current)
        saved_at = Time.current
      end

      finish(plan, "done", text: text)
    rescue Cancelled
      nil
    rescue Ai::ActionPlan::Error => e
      finish(plan, "error", text: text.to_s, error: e.message)
    rescue StandardError => e
      Rails.logger.error("Ai::ActionPlanJob: #{e.class}")
      finish(plan, "error", text: text.to_s, error: Ai::ActionPlan::GENERIC_ERROR)
    end

    private

    # Só sai de "running": um "Parar" (cancelled) feito no meio não é sobrescrito.
    def finish(plan, status, **attrs)
      AiPlan.where(id: plan.id, status: "running").update_all(attrs.merge(status: status, updated_at: Time.current))
    end
  end
end
