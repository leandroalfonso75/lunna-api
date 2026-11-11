# Chamada simples (sem streaming) à OpenRouter com o modelo de texto da empresa, pedindo um JSON de volta.
# Usada pelas sugestões de título e de ficha técnica da Curva ABC.
module Ai
  class JsonChat
    URL = "https://openrouter.ai/api/v1/chat/completions"
    DEFAULT_MODEL = "google/gemini-2.5-flash" # quando a empresa só cadastrou a chave (sem modelo de texto)
    VISION_MODEL = "google/gemini-2.5-flash"  # com imagens: modelo que lê fotos (o de texto da empresa pode não ler)

    class Error < StandardError; end

    # images: URLs de fotos enviadas junto (ex.: fotos do anúncio) — usa o modelo com visão.
    def self.call(company, system:, user:, http: nil, max_tokens: 2000, images: []) = new(company, system, user, http, max_tokens, images).call

    def initialize(company, system, user, http, max_tokens, images = [])
      @images = Array(images).compact.first(10)
      @company = company
      @system = system
      @user = user
      @http = http || Faraday.new { |f| f.options.timeout = 90; f.options.open_timeout = 10 }
      @max_tokens = max_tokens
    end

    def call
      raise Error, "Cadastre a chave da OpenRouter (Chave da API) em Configurações › Empresa." if @company.openrouter_api_key.blank?

      response = @http.post(URL) do |req|
        req.headers["Authorization"] = "Bearer #{@company.openrouter_api_key}"
        req.headers["Content-Type"] = "application/json"
        req.headers["X-Title"] = "Lunna"
        content = @images.any? ? [ { type: "text", text: @user } ] + @images.map { |url| { type: "image_url", image_url: { url: url } } } : @user
        model = @images.any? ? VISION_MODEL : (@company.ai_model.presence || DEFAULT_MODEL)
        req.body = { model: model, max_tokens: @max_tokens, reasoning: { enabled: false }, response_format: { type: "json_object" },
                     messages: [ { role: "system", content: @system }, { role: "user", content: content } ] }.to_json
      end
      raise Error, "A IA não respondeu agora (status #{response.status}). Tente de novo." unless (200...300).cover?(response.status)

      text = JSON.parse(response.body).dig("choices", 0, "message", "content").to_s
      JSON.parse(text[/\{.*\}/m] || "{}")
    rescue JSON::ParserError
      raise Error, "A IA devolveu uma resposta que o Lunna não entendeu. Tente de novo."
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError
      raise Error, "A IA demorou demais para responder. Tente de novo."
    end
  end
end
