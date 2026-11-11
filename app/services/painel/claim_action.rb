# Resolver a reclamação pelo Lunna (pedido do usuário em 04/11/2026), com as mesmas opções do Mercado Livre:
#   - allow_return   "Oferecer devolução"      POST /post-purchase/v1/claims/{id}/expected-resolutions/allow-return
#   - refund         "Reembolsar o dinheiro"   POST /post-purchase/v1/claims/{id}/expected-resolutions/refund
#   - partial_refund "Reembolso parcial"       POST /post-purchase/v1/claims/{id}/expected-resolutions/partial-refund
#                                               { percentage } (um dos percentuais de .../partial-refund/available-offers)
#   - open_dispute   "Falar com o Mercado Livre" (pedir mediação) POST /post-purchase/v1/claims/{id}/actions/open-dispute
# Escrita no ML que não se desfaz: só administradores, com confirmação (confirm: true), só quando o ML libera a ação
# para o vendedor (available_actions), registrada em ml_claim_actions; depois a reclamação é relida.
module Painel
  class ClaimAction
    Result = Struct.new(:ok, :message, :record, keyword_init: true)
    # ação do Lunna => ação que o ML precisa liberar ao vendedor
    REQUIRES = { "allow_return" => "allow_return", "refund" => "refund", "partial_refund" => "allow_partial_refund",
                 "open_dispute" => "open_dispute" }.freeze
    LABELS = { "allow_return" => "Oferecer devolução", "refund" => "Reembolsar o dinheiro", "partial_refund" => "Oferecer reembolso parcial",
               "open_dispute" => "Pedir ajuda do Mercado Livre (mediação)" }.freeze
    DONE = { "allow_return" => "Devolução oferecida: o Mercado Livre gera a etiqueta para o comprador devolver o produto.",
             "refund" => "Reembolso total feito: o Mercado Livre devolve o dinheiro ao comprador e encerra a reclamação.",
             "partial_refund" => "Reembolso parcial oferecido ao comprador; se ele aceitar, a reclamação é encerrada.",
             "open_dispute" => "Mediação pedida: a partir de agora as mensagens vão para o mediador do Mercado Livre." }.freeze

    def self.available(claim)
      return [] unless claim.status == "opened"

      actions = ClaimsQuery.seller_actions(claim).map { |a| a["action"] }
      REQUIRES.select { |_, needed| actions.include?(needed) }.keys
    end

    def self.partial_offers(account, claim_id)
      Ml::OAuth.refresh!(account)
      Ml::Client.new(access_token: account.reload.access_token).claim_partial_refund_offers(claim_id)
    end

    def self.call(account, claim_id, action:, user:, percentage: nil) = new(account, claim_id, action, user, percentage).call

    def initialize(account, claim_id, action, user, percentage)
      @account = account
      @claim = account.ml_claims.find_by!(claim_id: claim_id)
      @action = action.to_s
      @user = user
      @percentage = percentage.presence&.to_f
    end

    def call
      return Result.new(ok: false, message: "Ação desconhecida.") unless REQUIRES.key?(@action)
      unless self.class.available(@claim).include?(@action)
        return Result.new(ok: false, message: "O Mercado Livre não libera \"#{LABELS[@action]}\" nesta reclamação agora.")
      end
      return Result.new(ok: false, message: "Escolha o percentual do reembolso parcial.") if @action == "partial_refund" && !@percentage

      record = @account.ml_claim_actions.create!(claim_id: @claim.claim_id, user: @user, action: @action,
                                                 params: @percentage ? { percentage: @percentage } : {}, status: "pending")
      client = Ml::Client.new(access_token: fresh_token)
      response = client.claim_resolve(@claim.claim_id, @action, percentage: @percentage)
      record.update!(status: "done", response: response.is_a?(Hash) ? response : { "data" => response })
      refresh(client)
      Ml::ClaimRefreshJob.schedule(@account, @claim.claim_id) # relê de novo em 10 s e 60 s
      Result.new(ok: true, message: DONE[@action], record: record)
    rescue Ml::Client::Error => e
      record&.update!(status: "failed", error: e.message.truncate(500))
      Result.new(ok: false, message: "O Mercado Livre não aceitou: #{ml_message(e)}", record: record)
    rescue Ml::OAuth::Error
      record&.update!(status: "failed", error: "conta precisa ser autorizada de novo")
      Result.new(ok: false, message: "A conta do Mercado Livre precisa ser autorizada de novo.", record: record)
    end

    private

    def fresh_token
      Ml::OAuth.refresh!(@account)
      @account.reload.access_token
    end

    def refresh(client)
      attrs = Ml::Sync::ClaimsCenter.fetch_details(client, @claim, {})
      @claim.update_columns(attrs.merge(details_synced_at: Time.current, updated_at: Time.current))
    rescue Ml::Client::Error
      nil
    end

    def ml_message(error)
      body = error.respond_to?(:body) ? error.body.to_s : error.message.to_s
      parsed = JSON.parse(body[/\{.*\}/m].to_s) rescue {}
      parsed["message"].presence || parsed["error"].presence || error.message.truncate(160)
    end
  end
end
