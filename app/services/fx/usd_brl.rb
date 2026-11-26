# Cotação do dólar em reais para mostrar custos em R$ (fotos com IA cobradas em US$ pela OpenRouter; pedido do usuário
# em 25/11/2026). Fonte: AwesomeAPI (economia.awesomeapi.com.br, pública, sem chave), valor de venda ("ask"). Guarda a
# cotação por TTL no processo; se a fonte falhar, usa a última que deu certo e, sem nenhuma, devolve nil (a tela mostra
# em US$).
module Fx
  class UsdBrl
    URL = URI("https://economia.awesomeapi.com.br/json/last/USD-BRL")
    TTL = 6.hours
    MUTEX = Mutex.new

    class << self
      def rate
        MUTEX.synchronize do
          return @rate if @rate && @fetched_at && @fetched_at > TTL.ago

          fresh = fetch
          if fresh
            @rate = fresh
            @fetched_at = Time.current
          end
          @rate
        end
      end

      def reset! = MUTEX.synchronize { @rate = @fetched_at = nil }

      private

      def fetch
        res = Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: 3, read_timeout: 3) { |http| http.get(URL.request_uri) }
        return nil unless res.is_a?(Net::HTTPSuccess)

        value = JSON.parse(res.body).dig("USDBRL", "ask").to_f
        value.positive? ? value.round(4) : nil
      rescue StandardError => e
        Rails.logger.warn("Fx::UsdBrl: #{e.class} #{e.message}")
        nil
      end
    end
  end
end
