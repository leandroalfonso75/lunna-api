# GET /auth/olist/callback (público): o Olist devolve `code` e `state` aqui.
# Diferente do ML (que termina no front), a conexão é concluída direto na API,
# porque ainda não há tela do Olist no Lunna. O `state` é um UUID de uso único,
# criado por um admin logado (POST /api/olist/authorize), com validade de 1 h e
# preso à empresa dele: sem um state válido nada é gravado. No fim redireciona
# para o front com o resultado em `?olist=`.
module Auth
  class OlistCallbacksController < ApplicationController
    skip_before_action :authenticate!

    def show
      return redirect_with_result("cancelada") if params[:error].present?
      return redirect_with_result("link_invalido") if params[:code].blank? || params[:state].blank?
      return redirect_with_result("erro_config") unless Olist::OAuth.configured?

      state = consume_state(params[:state])
      return redirect_with_result("expirada") if state.nil?

      connect(state)
    rescue Olist::OAuth::Error => e
      Rails.logger.error("Olist callback: falha ao trocar code (#{e.class})")
      redirect_with_result("erro")
    end

    private

    def connect(state)
      data = Olist::OAuth.exchange_code(params[:code])
      return redirect_with_result("erro") if data["access_token"].blank? || data["refresh_token"].blank?

      connection = OlistConnection.find_or_initialize_by(company_id: state[:company_id])
      connection.connected_by_user_id = state[:user_id]
      Olist::OAuth.apply_tokens!(connection, data)

      redirect_with_result("conectado")
    end

    # Uso único: busca com lock e apaga. Expirado ou inexistente → nil.
    def consume_state(token)
      OlistOauthState.transaction do
        record = OlistOauthState.lock.find_by(state: token)
        next nil if record.nil? || record.created_at < OlistOauthState::TTL.ago

        result = { company_id: record.company_id, user_id: record.user_id }
        record.destroy!
        result
      end
    end

    def redirect_with_result(code)
      redirect_to "#{ENV.fetch("FRONT_URL")}/configuracoes?olist=#{code}", allow_other_host: true
    end
  end
end
