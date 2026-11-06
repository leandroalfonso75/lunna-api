# Cliente da API do Mercado Pago com o token do Mercado Livre (a mesma autorização da conta do ML). Somente leitura.
module Mp
  class Client
    BASE_URL = "https://api.mercadopago.com"
    class Error < StandardError
      attr_reader :status

      def initialize(status, message)
        @status = status
        super("Mercado Pago #{status}: #{message}")
      end
    end

    def initialize(access_token:, sleeper: ->(s) { sleep(s) })
      @access_token = access_token
      @sleeper = sleeper
    end

    # Pagamentos recebidos, por data de atualização (para pegar também reembolsos e liberações), 50 por página.
    def payments(begin_date:, end_date:, offset: 0, limit: 50)
      get_json("/v1/payments/search", { "sort" => "date_last_updated", "criteria" => "asc", "range" => "date_last_updated",
                                         "begin_date" => begin_date.utc.iso8601(3), "end_date" => end_date.utc.iso8601(3),
                                         "offset" => offset, "limit" => limit })
    end

    def release_reports = get_json("/v1/account/release_report/list")

    def release_report(file_name) = get("/v1/account/release_report/#{file_name}").body.to_s.dup.force_encoding("UTF-8")

    private

    def get_json(path, params = {}) = JSON.parse(get(path, params).body)

    def get(path, params = {})
      attempts = 0
      begin
        response = connection.get(path, params)
        raise Error.new(response.status, response.body.to_s[0, 160]) if response.status == 429 || response.status >= 500
        raise Error.new(response.status, response.body.to_s[0, 160]) unless (200...300).cover?(response.status)

        response
      rescue Error => e
        attempts += 1
        raise if attempts > 3 || !(e.status == 429 || e.status.to_i >= 500)

        @sleeper.call(5 * attempts)
        retry
      end
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL, headers: { "Authorization" => "Bearer #{@access_token}" }) { |f| f.options.timeout = 60 }
    end
  end
end
