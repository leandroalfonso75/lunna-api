# Cliente HTTP da API v3 do Olist ERP (antigo Tiny). Recebe a conexão da
# empresa, garante um access_token válido (renova perto de expirar) e fala com
# o ERP. Leituras (GET) repetem em 429/5xx. ESCRITAS (PUT/POST) NUNCA repetem
# sozinhas: repetir um lançamento de estoque duplicaria a movimentação.
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
    # 403: o app do Olist não tem permissão para este recurso (liberar no painel e reautorizar).
    class Forbidden < Error; end

    BASE_URL = "https://api.tiny.com.br/public-api/v3".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30
    MAX_ATTEMPTS = 3
    BODY_EXCERPT_SIZE = 200
    PAGE_SIZE = 100
    MAX_PAGES = 500

    STOCK_TYPES = { "B" => "Balanço", "E" => "Entrada", "S" => "Saída" }.freeze

    def initialize(connection, sleeper: ->(seconds) { sleep(seconds) })
      @connection = connection
      @sleeper = sleeper
    end

    # --- Leituras -----------------------------------------------------------

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

    # Saldos de estoque de todos os produtos (GET /estoque).
    def stock(params = {})
      get("/estoque", params)
    end

    def product_stock(id)
      get("/estoque/#{Integer(id)}")
    end

    # Movimentações de estoque do produto (GET /estoque/{id}/logs-movimentacao).
    def stock_movements(id, params = {})
      get("/estoque/#{Integer(id)}/logs-movimentacao", params)
    end

    # Todas as movimentações do produto (todas as páginas).
    def all_stock_movements(id)
      items = []
      MAX_PAGES.times do |page|
        result = stock_movements(id, limit: PAGE_SIZE, offset: page * PAGE_SIZE)
        batch = result["itens"] || []
        items.concat(batch)
        total = result.dig("paginacao", "total")
        break if batch.empty? || (total && items.size >= total)
      end
      items
    end

    # Percorre todas as páginas de uma listagem (`:products` ou `:stock`) e
    # devolve todos os itens. Para no total informado ou numa página vazia.
    def all(listing, **params)
      items = []
      MAX_PAGES.times do |page|
        result = public_send(listing, params.merge(limit: PAGE_SIZE, offset: page * PAGE_SIZE))
        batch = result["itens"] || []
        items.concat(batch)
        total = result.dig("paginacao", "total")
        break if batch.empty? || (total && items.size >= total)
      end
      items
    end

    # --- Escritas (nunca repetem sozinhas) -----------------------------------

    # PUT /produtos/{id}/preco
    def update_price(id, price:, promo_price: nil)
      body = { preco: price }
      body[:precoPromocional] = promo_price unless promo_price.nil?
      write(:put, "/produtos/#{Integer(id)}/preco", body)
    end

    # POST /estoque/{id} — lança uma movimentação: B balanço (define o saldo),
    # E entrada ou S saída.
    def post_stock(id, type:, quantity:, unit_price:, note: nil, deposit_id: nil, date: nil)
      raise ArgumentError, "tipo de estoque inválido" unless STOCK_TYPES.key?(type)

      body = { tipo: type, quantidade: quantity, precoUnitario: unit_price }
      body[:observacoes] = note if note.present?
      body[:data] = date if date.present?
      body[:deposito] = { id: Integer(deposit_id) } if deposit_id.present?
      write(:post, "/estoque/#{Integer(id)}", body)
    end

    private

    def get(path, params = {})
      ensure_usable!(path)
      attempt = 0

      loop do
        attempt += 1

        begin
          response = http.get(path.delete_prefix("/"), params) { |req| authorize(req) }
        rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
          raise Error.new(status: nil, path: path, body: e.message) if attempt >= MAX_ATTEMPTS

          @sleeper.call(0.9 * attempt)
          next
        end

        return parse(response.body) if (200...300).cover?(response.status)
        raise_for(response, path) unless retryable?(response.status) && attempt < MAX_ATTEMPTS

        @sleeper.call(0.9 * attempt)
      end
    end

    # Uma única tentativa: se falhar (inclusive por timeout), o chamador decide.
    def write(verb, path, body)
      ensure_usable!(path)

      response = http.public_send(verb, path.delete_prefix("/")) do |req|
        authorize(req)
        req.headers["Content-Type"] = "application/json"
        req.body = body.to_json
      end

      return parse(response.body) if (200...300).cover?(response.status)

      raise_for(response, path)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise Error.new(status: nil, path: path, body: e.message)
    end

    def ensure_usable!(path)
      if @connection.reauth_required?
        raise Error.new(status: 401, path: path, body: "conexão precisa ser refeita")
      end

      Olist::OAuth.refresh!(@connection)
    end

    def authorize(request)
      request.headers["Authorization"] = "Bearer #{@connection.access_token}"
    end

    def parse(body)
      body.to_s.strip.empty? ? {} : JSON.parse(body)
    end

    def retryable?(status) = status == 429 || status >= 500

    def raise_for(response, path)
      klass = { 404 => NotFound, 403 => Forbidden }.fetch(response.status, Error)
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
