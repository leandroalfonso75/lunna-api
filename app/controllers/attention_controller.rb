# Pontos vermelhos do menu (pedido do usuário em 08/11/2026): quantas reclamações, perguntas e mensagens aguardam o
# vendedor. Leitura leve, consultada pela tela a cada minuto.
# GET /api/attention?account_id= → { claims:, questions:, messages: }
class AttentionController < ApplicationController
  include CurrentAccount

  def show
    account = Current.account
    claims = account.ml_claims.where(status: "opened").select(:id, :status, :action_responsible, :players).to_a
                    .count { |c| Painel::ClaimsQuery.to_attend?(c) }
    render json: {
      claims: claims,
      questions: account.ml_questions.unanswered.count,
      # só as conversas em que dá para responder (as bloqueadas pelo ML não pedem ação)
      messages: account.ml_conversations.visible.where(last_from: "buyer", status: "active").count
    }
  end
end
