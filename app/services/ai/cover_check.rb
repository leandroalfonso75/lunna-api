# Curva ABC > Fotos (pedido do usuário em 04/11/2026): confere, com um modelo de visão da OpenRouter, se a foto escolhida
# como capa segue as regras do Mercado Livre para a foto principal: fundo branco (ou neutro claro), sem texto, sem logo
# ou marca d'água, sem bordas/molduras, produto inteiro e nítido, um produto só (sem montagem). Só avisa: o usuário pode
# publicar mesmo assim.
module Ai
  class CoverCheck
    URL = "https://openrouter.ai/api/v1/chat/completions"
    MODEL = "google/gemini-2.5-flash" # visão barata e rápida (~US$ 0,001 por checagem)
    RULES = {
      "white_background" => "fundo não é branco",
      "no_text" => "tem texto na imagem",
      "no_logo_watermark" => "tem logotipo, selo ou marca d'água",
      "no_border" => "tem borda ou moldura",
      "whole_product" => "o produto não aparece inteiro",
      "single_scene" => "é montagem ou colagem de várias imagens",
      "sharp" => "imagem sem nitidez"
    }.freeze

    class Error < StandardError; end

    def self.call(company, image_url, http: nil) = new(company, image_url, http).call

    def initialize(company, image_url, http)
      @company = company
      @image_url = image_url
      @http = http || Faraday.new { |f| f.options.timeout = 60 }
    end

    def call
      raise Error, "Cadastre a chave da OpenRouter (Chave da API) em Configurações › Empresa." if @company.openrouter_api_key.blank?

      response = @http.post(URL) do |req|
        req.headers["Authorization"] = "Bearer #{@company.openrouter_api_key}"
        req.headers["Content-Type"] = "application/json"
        req.headers["X-Title"] = "Lunna"
        req.body = body.to_json
      end
      raise Error, "A checagem da capa não respondeu agora (status #{response.status})." unless (200...300).cover?(response.status)

      parse(JSON.parse(response.body).dig("choices", 0, "message", "content").to_s)
    end

    private

    def body
      prompt = <<~TXT
        Você confere a FOTO PRINCIPAL (capa) de um anúncio do Mercado Livre. Responda só com um JSON com estas chaves
        booleanas (true = cumpre a regra): #{RULES.keys.join(', ')}. white_background: fundo branco puro ou quase branco;
        no_text: nenhum texto, número ou preço sobre a imagem; no_logo_watermark: sem logotipo extra, selo ou marca d'água
        (a marca impressa no próprio produto não conta); no_border: sem borda/moldura; whole_product: produto inteiro, sem
        cortes; single_scene: uma foto só, não é colagem; sharp: nítida.
      TXT
      { model: MODEL, response_format: { type: "json_object" },
        messages: [ { role: "user", content: [ { type: "text", text: prompt }, { type: "image_url", image_url: { url: @image_url } } ] } ] }
    end

    def parse(text)
      data = JSON.parse(text[/\{.*\}/m] || "{}")
      reasons = RULES.filter_map { |key, label| label if data[key] == false }
      { ok: reasons.empty?, reasons: reasons }
    rescue JSON::ParserError
      raise Error, "A checagem da capa não entendeu a resposta da IA; tente de novo."
    end
  end
end
