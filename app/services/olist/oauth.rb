# Fluxo OAuth 2.0 do Olist ERP, API v3 (https://api-docs.erp.olist.com):
# gera a URL de autorização, troca o code por tokens e renova o access_token
# (vale 4 h) com o refresh_token (vale 1 dia).
module Olist
  class OAuth
    class Error < StandardError; end

    AUTH_BASE = "https://accounts.tiny.com.br/realms/tiny/protocol/openid-connect".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    DEFAULT_EXPIRES_IN = 4.hours.to_i
    DEFAULT_REFRESH_EXPIRES_IN = 1.day.to_i
    RENEW_WINDOW = 10.minutes

    class << self
      def configured?
        ENV["OLIST_CLIENT_ID"].present? && ENV["OLIST_CLIENT_SECRET"].present?
      end

      # Precisa ser idêntica à "URL de redirecionamento" cadastrada no app do Olist.
      def redirect_uri
        "#{ENV.fetch("API_URL")}/auth/olist/callback"
      end

      def authorize_url(state)
        params = {
          client_id: ENV["OLIST_CLIENT_ID"],
          redirect_uri: redirect_uri,
          scope: "openid",
          response_type: "code",
          state: state
        }
        "#{AUTH_BASE}/auth?#{params.to_query}"
      end

      def exchange_code(code)
        request_token(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
      end

      def refresh(refresh_token)
        request_token(grant_type: "refresh_token", refresh_token: refresh_token)
      end

      # Grava tokens recebidos do Olist na conexão (o refresh_token pode ser
      # rotacionado: usa o novo se vier, senão mantém o atual).
      def apply_tokens!(connection, data)
        connection.assign_attributes(
          access_token: data["access_token"],
          refresh_token: data["refresh_token"].presence || connection.refresh_token,
          expires_at: Time.current + (data["expires_in"] || DEFAULT_EXPIRES_IN),
          refresh_expires_at: Time.current + (data["refresh_expires_in"] || DEFAULT_REFRESH_EXPIRES_IN),
          status: "active",
          last_error: nil
        )
        connection.save!
      end

      # Renova o access_token da conexão dentro de um lock; só chama o Olist se
      # faltarem menos de 10 min para expirar (ou se `force`). Falha marca a
      # conexão como reauth_required — gravada mesmo levantando o erro depois
      # do commit (mesmo cuidado de Ml::OAuth.refresh!).
      def refresh!(connection, force: false)
        failure = nil

        connection.with_lock do
          next if !force && connection.expires_at.present? && connection.expires_at >= RENEW_WINDOW.from_now

          begin
            apply_tokens!(connection, refresh(connection.refresh_token))
          rescue Error => e
            connection.update!(
              status: "reauth_required",
              last_error: "Falha ao renovar o acesso ao Olist ERP. Conecte de novo."
            )
            failure = e
          end
        end

        raise failure if failure

        connection
      end

      private

      def request_token(params)
        response = http.post("token", {
          client_id: ENV["OLIST_CLIENT_ID"],
          client_secret: ENV["OLIST_CLIENT_SECRET"]
        }.merge(params))

        unless (200...300).cover?(response.status)
          raise Error, "Falha ao trocar/renovar token do Olist ERP (status #{response.status})"
        end

        JSON.parse(response.body)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise Error, "Falha ao contactar o Olist ERP (#{e.class})"
      rescue JSON::ParserError
        raise Error, "Resposta inválida do Olist ERP ao trocar/renovar token"
      end

      def http
        @http ||= Faraday.new(url: "#{AUTH_BASE}/") do |f|
          f.request :url_encoded
          f.options.open_timeout = OPEN_TIMEOUT
          f.options.timeout = READ_TIMEOUT
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
