# Curva ABC > Fotos (pedido do usuário em 04/11/2026): gera imagens novas do anúncio pela OpenRouter (modelo de
# imagem da empresa, `companies.ai_image_model`), usando como referência as fotos do próprio anúncio escolhidas e as
# anexadas pelo usuário. Uma chamada por imagem, cada uma pedindo uma cena/ângulo diferente. Não publica nada.
module Ai
  class PhotoGenerator
    URL = "https://openrouter.ai/api/v1/chat/completions"
    DEFAULT_MODEL = "google/gemini-2.5-flash-image"
    CONFIG_ERROR = "Cadastre a chave da OpenRouter em Configurações › Empresa para gerar fotos."
    MAX_REFERENCES = 6
    VARIATIONS = [
      "foto principal em fundo branco puro, produto inteiro e centralizado, iluminação de estúdio suave",
      "produto em uso, num ambiente real e bonito que combine com quem compra este produto",
      "detalhe aproximado (close) mostrando acabamento, textura e qualidade do produto",
      "produto de outro ângulo (lateral ou três quartos), fundo neutro claro",
      "composição mostrando o conteúdo da embalagem/kit, todos os itens organizados sobre fundo claro",
      "cena de estilo de vida com o produto em destaque, luz natural"
    ].freeze

    class Error < StandardError; end

    def self.call(job, client: nil, http: nil) = new(job, client: client, http: http).call

    def initialize(job, client: nil, http: nil)
      @job = job
      @company = job.ml_account.company
      @client = client
      @http = http
    end

    def call
      raise Error, CONFIG_ERROR if @company.openrouter_api_key.blank?

      refs = reference_urls
      raise Error, "Escolha ao menos uma foto de referência (do anúncio ou anexada)." if refs.empty?

      start = @job.generated.size
      (start...@job.count).each do |i|
        bytes, mime = generate_one(refs, i)
        @job.photos.create!(kind: "gerada", position: i, mime: mime, data: bytes)
      end
    end

    private

    def model = @company.ai_image_model.presence || DEFAULT_MODEL

    def reference_urls
      (Array(@job.reference_urls) + @job.uploaded_references.map(&:data_url)).first(MAX_REFERENCES)
    end

    def prompt(index)
      scene = VARIATIONS[index % VARIATIONS.size]
      extra = @job.instructions.present? ? "\nPedido do vendedor: #{@job.instructions}" : ""
      <<~TXT
        Crie UMA foto de produto para um anúncio do Mercado Livre (imagem #{index + 1} de #{@job.count}).
        As imagens anexadas são o produto real: mantenha o produto IDÊNTICO (formato, cores, marca, rótulos, peças e
        proporções); não invente acessórios nem mude o modelo.
        Cena desta imagem: #{scene}.
        Regras do Mercado Livre: sem textos, sem logotipos extras, sem marcas d'água, sem bordas, sem preço; formato
        quadrado (1:1), alta resolução, produto nítido ocupando boa parte da imagem.#{extra}
      TXT
    end

    def generate_one(refs, index)
      content = [ { type: "text", text: prompt(index) } ] + refs.map { |u| { type: "image_url", image_url: { url: u } } }
      body = { model: model, modalities: %w[image text], messages: [ { role: "user", content: content } ] }
      response = http.post(URL) do |req|
        req.headers["Authorization"] = "Bearer #{@company.openrouter_api_key}"
        req.headers["Content-Type"] = "application/json"
        req.headers["X-Title"] = "Lunna"
        req.body = body.to_json
      end
      raise Error, error_message(response.status) unless (200...300).cover?(response.status)

      url = JSON.parse(response.body).dig("choices", 0, "message", "images", 0, "image_url", "url").to_s
      match = url.match(%r{\Adata:(image/[a-z+]+);base64,(.+)\z}m)
      raise Error, "A OpenRouter não devolveu imagem (o modelo \"#{model}\" gera imagens?)." unless match

      [ Base64.decode64(match[2]), match[1] ]
    end

    def error_message(status)
      case status
      when 401, 403 then "A OpenRouter recusou a chave. Confira em Configurações › Empresa."
      when 402 then "Sem créditos na OpenRouter."
      when 400, 404 then "A OpenRouter não aceitou o modelo de imagem \"#{model}\"."
      when 429 then "A OpenRouter está limitando os pedidos agora; tente de novo em instantes."
      else "A OpenRouter não respondeu (status #{status})."
      end
    end

    def http
      @http ||= Faraday.new { |f| f.options.timeout = 180 }
    end
  end
end
