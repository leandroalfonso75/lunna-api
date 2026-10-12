# Cliente HTTP SOMENTE-LEITURA da API v3 do Olist ERP (antigo Tiny). Recebe a
# conexão da empresa, garante um access_token válido (renova perto de expirar)
# e só faz GET. Nenhuma escrita no ERP.
module Olist
  class Client
    class Error < StandardError
      attr_reader :status, :path

      def initialize(status:, path:, body: nil)
        @status = status
        @path = path
        detail = body.presence && " — #{body}"
        super("Olist::Client: #{status || "falha de conexão"} em #{path}#{detail}")
      end
    end

    class NotFound < Error; end

    BASE_URL = "https://api.tiny.com.br/public-api/v3".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30
    MAX_ATTEMPTS = 3
    BODY_EXCERPT_SIZE = 200

    def initialize(connection, sleeper: ->(seconds) { sleep(seconds) })
      @connection = connection
      @sleeper = sleeper
    end

    # Listagem de produtos (GET /produtos). `params`: nome, codigo, gtin,
    # situacao (A/I/E), dataCriacao, dataAlteracao, limit, offset.
    def products(params = {})
      get("/produtos", params)
    end

    def product(id)
      get("/produtos/#{Integer(id)}")
    end

    # Histórico de custos do produto (GET /produtos/{id}/custos).
    def product_costs(id, params = {})
      get("/produtos/#{Integer(id)}/custos", params)
    end

    private

    def get(path, params = {})
      if @connection.reauth_required?
        raise Error.new(status: 401, path: path, body: "conexão precisa ser refeita")
      end

      Olist::OAuth.refresh!(@connection)
      attempt = 0

      loop do
        attempt += 1

        begin
          response = http.get(path.delete_prefix("/"), params) do |req|
            req.headers["Authorization"] = "Bearer #{@connection.access_token}"
          end
        rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
          raise Error.new(status: nil, path: path, body: e.message) if attempt >= MAX_ATTEMPTS

          @sleeper.call(0.9 * attempt)
          next
        end

        return JSON.parse(response.body) if (200...300).cover?(response.status)
        raise_for(response, path) unless retryable?(response.status) && attempt < MAX_ATTEMPTS

        @sleeper.call(0.9 * attempt)
      end
    end

    def retryable?(status) = status == 429 || status >= 500

    def raise_for(response, path)
      klass = response.status == 404 ? NotFound : Error
      raise klass.new(status: response.status, path: path, body: response.body.to_s.byteslice(0, BODY_EXCERPT_SIZE))
    end

    def http
      @http ||= Faraday.new(url: "#{BASE_URL}/") do |f|
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = READ_TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
