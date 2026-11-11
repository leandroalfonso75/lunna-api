# Responder uma reclamação pelo Lunna (pedido do usuário em 03/11/2026): manda a mensagem na reclamação do Mercado
# Livre (POST /post-purchase/v1/claims/{id}/actions/send-message). É uma escrita no ML que não se desfaz:
#   - só administradores, com confirmação explícita (confirm: true) a cada envio;
#   - só para quem o ML libera agora (ação send_message_to_complainant / send_message_to_mediator do vendedor);
#   - fica registrada em ml_claim_replies (quem, quando, para quem, texto, resultado) antes e depois da chamada;
#   - depois de enviada, a reclamação é relida (mensagens e situação).
module Painel
  class ClaimReply
    Result = Struct.new(:ok, :message, :reply, keyword_init: true)
    MAX_LENGTH = 3500
    RECEIVER_ACTIONS = { "complainant" => "send_message_to_complainant", "mediator" => "send_message_to_mediator" }.freeze

    def self.call(account, claim_id, receiver:, text:, user:)
      new(account, claim_id, receiver, text, user).call
    end

    def initialize(account, claim_id, receiver, text, user)
      @account = account
      @claim = account.ml_claims.find_by!(claim_id: claim_id)
      @receiver = receiver.to_s
      @text = text.to_s.strip
      @user = user
    end

    def call
      return Result.new(ok: false, message: "Escreva a mensagem.") if @text.blank?
      return Result.new(ok: false, message: "A mensagem passou de #{MAX_LENGTH} caracteres.") if @text.size > MAX_LENGTH
      unless ClaimsQuery.reply_targets(@claim).include?(@receiver)
        return Result.new(ok: false, message: "O Mercado Livre não libera mensagem para #{@receiver == 'mediator' ? 'o mediador' : 'o comprador'} nesta reclamação agora.")
      end

      reply = @account.ml_claim_replies.create!(claim_id: @claim.claim_id, user: @user, receiver_role: @receiver, message: @text, status: "pending")
      client = Ml::Client.new(access_token: fresh_token)
      response = client.claim_send_message(@claim.claim_id, receiver_role: @receiver, message: @text)
      reply.update!(status: "sent", response: response.is_a?(Hash) ? response : {})
      refresh(client)
      Ml::ClaimRefreshJob.schedule(@account, @claim.claim_id) # relê de novo em 10 s e 60 s (o ML processa a resposta)
      Result.new(ok: true, message: "Mensagem enviada na reclamação no Mercado Livre.", reply: reply)
    rescue Ml::Client::Error => e
      reply&.update!(status: "failed", error: e.message.truncate(500))
      Result.new(ok: false, message: "O Mercado Livre não aceitou a mensagem: #{ml_message(e)}", reply: reply)
    rescue Ml::OAuth::Error
      reply&.update!(status: "failed", error: "conta precisa ser autorizada de novo")
      Result.new(ok: false, message: "A conta do Mercado Livre precisa ser autorizada de novo.", reply: reply)
    end

    private

    def fresh_token
      Ml::OAuth.refresh!(@account)
      @account.reload.access_token
    end

    # Relê a reclamação na hora para a mensagem aparecer (o resto da importação segue normal).
    def refresh(client)
      attrs = Ml::Sync::ClaimsCenter.fetch_details(client, @claim, {})
      @claim.update_columns(attrs.merge(details_synced_at: Time.current, updated_at: Time.current))
    rescue Ml::Client::Error
      nil
    end

    def ml_message(error)
      body = error.respond_to?(:body) ? error.body.to_s : error.message.to_s
      parsed = JSON.parse(body[/\{.*\}/m].to_s) rescue {}
      detail = parsed["message"].presence || parsed["error"].presence
      return "sem permissão de escrita em reclamações no aplicativo do Lunna no Mercado Livre (403)" if error.status == 403 && detail.to_s =~ /policy|forbidden|scope/i

      detail || error.message.truncate(160)
    end
  end
end
