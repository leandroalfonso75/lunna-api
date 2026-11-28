# Fluxo OAuth 2.0 do Mercado Livre (DECISOES §5, SPEC 2): gera a URL de
# autorização, troca o code por tokens e renova o access_token da conta.
module Ml
  class OAuth
    class Error < StandardError; end
    # O Mercado Livre recusou o acesso de verdade (ex.: invalid_grant): só aqui a conta vira "autorizar de novo".
    class RevokedError < Error; end
    # Falha passageira (rede, tempo esgotado, 5xx, limite de chamadas): tenta de novo na próxima rodada, sem parar a conta.
    class TransientError < Error; end

    BASE_URL = "https://api.mercadolibre.com"
    AUTHORIZATION_URL = "https://auth.mercadolivre.com.br/authorization"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    DEFAULT_EXPIRES_IN = 21_600
    RENEW_WINDOW = 10.minutes
    # Conta marcada "autorizar de novo": tenta renovar sozinha até AUTO_RETRIES vezes, uma a cada AUTO_RETRY_EVERY
    # (28/11/2026: em 27/11 o token ainda valia e a conta ficou 20 horas parada).
    AUTO_RETRIES = 6
    AUTO_RETRY_EVERY = 15.minutes
    REVOKED_STATUSES = [ 400, 401, 403 ].freeze

    class << self
      def configured?
        ENV["ML_CLIENT_ID"].present? && ENV["ML_CLIENT_SECRET"].present?
      end

      def redirect_uri
        "#{ENV.fetch("API_URL")}/auth/ml/callback"
      end

      def authorize_url(state)
        params = {
          response_type: "code",
          client_id: ENV["ML_CLIENT_ID"],
          redirect_uri: redirect_uri,
          state: state
        }
        "#{AUTHORIZATION_URL}?#{params.to_query}"
      end

      def exchange_code(code)
        request_token(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
      end

      def refresh(refresh_token)
        request_token(grant_type: "refresh_token", refresh_token: refresh_token)
      end

      # Desde 28/11/2026: só RevokedError (o ML recusou o acesso) marca reauth_required; TransientError (rede, 5xx,
      # 429) deixa a conta ativa e registra o motivo — a próxima rodada tenta de novo.
      #
      # Renova o access_token da conta dentro de um lock (recarrega a linha);
      # só chama o ML se faltarem menos de 10 min para expirar. Grava sempre o
      # novo refresh_token (o ML rotaciona), mantendo o antigo se a resposta
      # não trouxer um novo. Falha marca a conta como reauth_required.
      #
      # A falha precisa ficar gravada mesmo o método levantando erro — por
      # isso ela é aplicada e o `raise` acontece só depois que `with_lock`
      # (que roda tudo numa transação) já commitou, nunca dentro do bloco:
      # um `raise` dentro do bloco desfaria o próprio update de reauth_required.
      def refresh!(account)
        failure = nil

        account.with_lock do
          next if account.expires_at.present? && account.expires_at >= RENEW_WINDOW.from_now

          begin
            data = refresh(account.refresh_token)

            account.update!(
              access_token: data["access_token"],
              refresh_token: data["refresh_token"].presence || account.refresh_token,
              expires_at: Time.current + (data["expires_in"] || DEFAULT_EXPIRES_IN),
              scope: data["scope"],
              status: "active",
              last_error: nil,
              auth_retry_count: 0,
              auth_retry_at: nil
            )
          rescue TransientError => e
            account.update!(last_error: "Falha passageira ao renovar o acesso ao Mercado Livre (#{e.message}). Nova tentativa na próxima rodada.")
            failure = e
          rescue Error => e
            account.update!(
              status: "reauth_required",
              last_error: "Falha ao renovar token do Mercado Livre. Autorize de novo."
            )
            failure = e
          end
        end

        raise failure if failure

        account
      end

      # Conta marcada "autorizar de novo": tenta renovar com o acesso salvo (o ML às vezes recusa por instantes e o
      # token continua valendo). Até AUTO_RETRIES vezes, uma a cada AUTO_RETRY_EVERY. => true se voltou a valer.
      def auto_retry!(account)
        return false unless account.status == "reauth_required" && account.refresh_token.present?
        return false if account.auth_retry_count >= AUTO_RETRIES
        return false if account.auth_retry_at && account.auth_retry_at > AUTO_RETRY_EVERY.ago

        account.update!(auth_retry_count: account.auth_retry_count + 1, auth_retry_at: Time.current)
        data = refresh(account.refresh_token)
        account.update!(
          access_token: data["access_token"], refresh_token: data["refresh_token"].presence || account.refresh_token,
          expires_at: Time.current + (data["expires_in"] || DEFAULT_EXPIRES_IN), scope: data["scope"],
          status: "active", last_error: nil, auth_retry_count: 0, auth_retry_at: nil
        )
        true
      rescue Error => e
        account.update_columns(last_error: "Falha ao renovar token do Mercado Livre. Autorize de novo. (tentativa automática #{account.auth_retry_count} de #{AUTO_RETRIES}: #{e.message})")
        false
      end

      private

      def request_token(params)
        response = connection.post("/oauth/token", {
          client_id: ENV["ML_CLIENT_ID"],
          client_secret: ENV["ML_CLIENT_SECRET"]
        }.merge(params))

        unless (200...300).cover?(response.status)
          kind = REVOKED_STATUSES.include?(response.status) ? RevokedError : TransientError
          detail = (JSON.parse(response.body)["error"] rescue nil)
          raise kind, "Falha ao trocar/renovar token do Mercado Livre (status #{response.status}#{detail ? ", #{detail}" : ''})"
        end

        JSON.parse(response.body)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError, JSON::ParserError => e
        raise TransientError, "Falha ao contactar o Mercado Livre (#{e.class})"
      end

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :url_encoded
          f.options.open_timeout = OPEN_TIMEOUT
          f.options.timeout = READ_TIMEOUT
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
