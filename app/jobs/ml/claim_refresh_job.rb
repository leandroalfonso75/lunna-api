# Relê uma reclamação no Mercado Livre (detalhe, mensagens, responsável) logo depois de uma resposta: na hora e de novo
# alguns segundos depois, o tempo do ML processar (pedido do usuário em 10/11/2026: sair de "A atender" imediatamente).
module Ml
  class ClaimRefreshJob < ApplicationJob
    queue_as :default

    def self.refresh_now(account, claim_id)
      claim = account.ml_claims.find_by(claim_id: claim_id)
      return nil unless claim

      Ml::OAuth.refresh!(account)
      client = Ml::Client.new(access_token: account.reload.access_token)
      attrs = Ml::Sync::ClaimsCenter.fetch_details(client, claim, {})
      claim.update_columns(attrs.merge(details_synced_at: Time.current, updated_at: Time.current))
      claim.reload
    rescue Ml::Client::Error, Ml::OAuth::Error
      claim
    end

    # Agenda as releituras de depois (10 s e 60 s).
    def self.schedule(account, claim_id)
      [ 10.seconds, 60.seconds ].each { |wait| set(wait: wait).perform_later(account.id, claim_id) }
    end

    def perform(account_id, claim_id)
      account = MlAccount.find_by(id: account_id)
      self.class.refresh_now(account, claim_id) if account
    end
  end
end
