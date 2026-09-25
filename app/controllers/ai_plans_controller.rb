# POST /api/items/:id/ai-plan?account_id= → plano de ação com IA (SPEC 9), em
# streaming (SSE). Anúncio de outra conta/empresa → 404 antes de abrir o
# stream; a partir do primeiro `write` só dá pra sinalizar erro via
# `event: error` (não dá mais pra renderizar JSON).
class AiPlansController < ApplicationController
  include CurrentAccount
  include ActionController::Live

  rate_limit to: 10, within: 1.minute,
    by: -> { Current.company&.id || request.remote_ip },
    with: -> { render_errors([ "Muitas tentativas. Tente de novo em instantes." ], status: :too_many_requests) }

  def create
    account = Current.account
    account.item_metrics.find_by!(item_id: params[:id])

    detail, row, context = Abc::Report.item_for_prompt(account, params[:id])
    prompt = Ai::ActionPlanPrompt.call(detail, row, context)

    # Libera a conexão com o banco antes de segurar a thread na Claude API.
    ActiveRecord::Base.connection_handler.clear_active_connections!

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    begin
      Ai::ActionPlan.stream(Current.company, prompt) { |text| response.stream.write("data: #{text.to_json}\n\n") }
      response.stream.write("event: done\ndata: {}\n\n")
    rescue Ai::ActionPlan::Error => e
      response.stream.write("event: error\ndata: #{ { message: e.message }.to_json }\n\n")
    rescue ActionController::Live::ClientDisconnected
      nil # cliente cancelou — só para de gerar
    rescue StandardError => e
      Rails.logger.error("AiPlansController: erro inesperado (#{e.class})")
      response.stream.write("event: error\ndata: #{ { message: "Não foi possível gerar o plano agora. Tente de novo." }.to_json }\n\n")
    ensure
      response.stream.close
    end
  end
end
