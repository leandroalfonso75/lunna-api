# DECISOES §10 — chama a OpenRouter (API compatível com OpenAI) em streaming,
# com a chave e o modelo da própria empresa. Faraday puro (sem SDK): lê o SSE
# via `on_data`, emitindo só os deltas de texto (`choices[0].delta.content`).
module Ai
  class ActionPlan
    class Error < StandardError; end

    URL = "https://openrouter.ai/api/v1/chat/completions"
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 120
    MAX_TOKENS = 4096

    CONFIG_ERROR = "Configure a chave e o modelo da OpenRouter em Configurações › Empresa."
    GENERIC_ERROR = "Não foi possível gerar o plano agora. Tente de novo."

    def self.stream(company, prompt, &block) = new(company, prompt).call(&block)

    def initialize(company, prompt)
      @company = company
      @prompt = prompt
    end

    def call(&block)
      raise Error, CONFIG_ERROR unless @company.ai_configured?

      status = nil
      buffer = +""
      error_body = +""

      response = connection.post(URL) do |req|
        req.headers["Authorization"] = "Bearer #{@company.openrouter_api_key}"
        req.headers["HTTP-Referer"] = ENV["FRONT_URL"] if ENV["FRONT_URL"].present?
        req.headers["X-Title"] = "Lunna"
        req.body = request_body
        req.options.on_data = proc do |chunk, _bytes, env|
          status = env.status

          if success?(status)
            buffer << chunk
            consume(buffer, &block)
          else
            error_body << chunk
          end
        end
      end

      status ||= response.status
      return if success?(status)

      Rails.logger.error("Ai::ActionPlan: status #{status} da OpenRouter — #{error_body.byteslice(0, 200)}")
      raise_for_status(status)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError
      raise Error, GENERIC_ERROR
    end

    private

    def request_body
      {
        model: @company.ai_model,
        stream: true,
        max_tokens: MAX_TOKENS,
        messages: [
          { role: "system", content: @prompt[:system] },
          { role: "user", content: @prompt[:user] }
        ]
      }
    end

    # Processa as linhas completas já acumuladas no buffer (mutado em lugar),
    # deixando uma linha parcial (sem `\n` ainda) para o próximo chunk.
    def consume(buffer, &block)
      while (index = buffer.index("\n"))
        handle_line(buffer.slice!(0..index).chomp, &block)
      end
    end

    def handle_line(line, &block)
      return if line.empty? || line.start_with?(":") || !line.start_with?("data:")

      data = line.delete_prefix("data:").strip
      return if data == "[DONE]"

      event = JSON.parse(data)
      raise Error, GENERIC_ERROR if event["error"]

      content = event.dig("choices", 0, "delta", "content")
      block.call(content) if content
    end

    def success?(status) = status && (200...300).cover?(status)

    def raise_for_status(status)
      message =
        case status
        when 401, 403 then "A OpenRouter recusou a chave. Confira em Configurações › Empresa."
        when 402 then "Sem créditos na OpenRouter."
        when 429 then "Limite de uso atingido, tente em instantes."
        when 400, 404 then "A OpenRouter não aceitou o modelo \"#{@company.ai_model}\". Confira o nome em Configurações › Empresa."
        else GENERIC_ERROR
        end

      raise Error, message
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.request :json
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = READ_TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
