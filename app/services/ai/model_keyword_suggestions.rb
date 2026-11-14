# Curva ABC > "Alterar modelo AGORA" (pedido do usuário em 14/11/2026): 3 opções de texto para o campo Modelo da ficha
# técnica, feitas de palavras-chave (as mais buscadas para o produto no Mercado Livre e no Google), e o modelo real do
# produto para "Modelo detalhado". Não publica nada.
module Ai
  class ModelKeywordSuggestions
    SYSTEM = <<~TXT.freeze
      Você é especialista em SEO do Mercado Livre Brasil. O campo "Modelo" da ficha técnica entra na busca do Mercado Livre
      e aceita até LIMITE caracteres. Em vez do código do modelo, ele será preenchido com PALAVRAS-CHAVE que o comprador
      digita para achar este produto. O modelo de verdade do produto vai no campo "Modelo detalhado".
      Regras:
      - Use as palavras mais buscadas para o produto no Mercado Livre (veja as tendências da categoria, quando houver) e no
        Google: nomes populares do produto, sinônimos, usos, público e características que o comprador busca.
      - Prefira termos que NÃO estão no título (o título já é buscado); não repita palavras dentro do texto.
      - Só termos verdadeiros para este produto (confira título, ficha e descrição); não use marcas de outras empresas,
        palavras promocionais (oferta, promoção, frete grátis, barato, desconto, original, novo, garantia) nem símbolos;
        palavras separadas por espaço, em minúsculas, sem vírgulas.
      - Cada opção com no máximo LIMITE caracteres (conte espaços), aproveitando o espaço (ideal: perto do limite).
      - "detailed_model": o modelo/código real do produto (ex.: o modelo atual, se for um código de modelo; ou o que aparece
        no título/descrição). Vazio se não souber; nunca invente.
      Responda só com JSON: {"options": [{"model": "...", "why": "frase curta com o porquê"}], "detailed_model": "..."} com
      exatamente 3 opções diferentes entre si.
    TXT

    def self.call(company, info, description: nil, http: nil)
      limit = info[:max_length] || 110
      user = <<~TXT
        Título: #{info[:title]}
        Marca: #{info[:brand].presence || '—'}
        Modelo atual: #{info[:model].presence || '—'} · Modelo detalhado atual: #{info[:detailed_model].presence || '—'}
        Ficha técnica: #{Array(info[:attributes]).join('; ')}
        Mais buscadas na categoria (Mercado Livre): #{Array(info[:trends]).first(30).join(', ').presence || '—'}
        Descrição (trecho): #{description.to_s.squish.first(1500).presence || '—'}
        Limite: #{limit} caracteres.
      TXT
      data = Ai::JsonChat.call(company, system: SYSTEM.gsub("LIMITE", limit.to_s), user: user, http: http)
      options = Array(data["options"]).filter_map do |o|
        text = (o.is_a?(Hash) ? o["model"] : o).to_s.squish
        next if text.blank?

        text = cut(text, limit)
        { model: text, why: o.is_a?(Hash) ? o["why"].to_s : "", length: text.length }
      end.uniq { |o| o[:model].downcase }.first(3)
      detailed = data["detailed_model"].to_s.squish.first(255).presence || info[:detailed_model].presence || info[:model]
      { options: options, detailed_model: detailed, max_length: limit }
    end

    # corta no limite sem deixar palavra pela metade
    def self.cut(text, limit)
      return text if text.length <= limit

      text.first(limit + 1).sub(/\s+\S*\z/, "").strip
    end
  end
end
