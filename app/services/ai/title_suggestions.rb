# Curva ABC > "Sugerir títulos": 5 títulos com SEO para o Mercado Livre (busca do marketplace, Google e e-commerce em
# geral), a partir do anúncio (título, marca, modelo, ficha técnica, descrição). Não publica nada.
module Ai
  class TitleSuggestions
    SYSTEM = <<~TXT.freeze
      Você é especialista em SEO de anúncios do Mercado Livre Brasil e de e-commerce. Escreva títulos que o comprador
      encontra na busca do Mercado Livre e do Google. Regras do Mercado Livre e de boas práticas:
      - Estrutura: produto (o que é) + marca + modelo/linha + características que o comprador filtra e busca
        (material, tamanho, capacidade, voltagem, cor quando importa, quantidade no kit).
      - As palavras mais buscadas primeiro; termos que o comprador realmente digita (sinônimos populares quando couber).
      - Sem palavras promocionais ou sobre preço/frete/condição de venda (oferta, promoção, frete grátis, barato,
        desconto, imperdível, liquidação, original, novo, garantia), sem símbolos (! * / | - ,) e sem tudo em maiúsculas.
      - Não repetir palavras, não inventar características que não estão nos dados.
      - Cada título com no máximo LIMITE caracteres (conte espaços) e aproveitando o espaço (ideal: perto do limite).
      Responda só com JSON: {"titles": [{"title": "...", "why": "frase curta com o porquê"}]} com exatamente 5 títulos
      diferentes entre si.
    TXT

    def self.call(company, info, description: nil, http: nil)
      limit = info[:max_length] || 60
      variation = info[:mode] == "family_name" && info[:family_name].present? ? info[:title].to_s.delete_prefix(info[:family_name].to_s).strip : ""
      note = if info[:mode] == "family_name"
        "O anúncio está no modelo User Products: o texto vira o NOME DA FAMÍLIA e o Mercado Livre acrescenta sozinho a variação "           "ao título exibido#{variation.present? ? " (hoje: \"#{variation}\")" : ''}. NÃO inclua cor, voltagem, tamanho, sabor ou outra "           "variação no texto; deixe espaço para ela."
      else
        ""
      end
      user = <<~TXT
        Título atual: #{info[:title]}
        Nome da família (family_name): #{info[:family_name].presence || '—'}
        Marca: #{info[:brand].presence || '—'} · Modelo: #{info[:model].presence || '—'}
        Ficha técnica: #{Array(info[:attributes]).join('; ')}
        Descrição (trecho): #{description.to_s.squish.first(1500).presence || '—'}
        #{note}
        Limite: #{limit} caracteres.
      TXT
      data = Ai::JsonChat.call(company, system: SYSTEM.sub("LIMITE", limit.to_s), user: user, http: http)
      Array(data["titles"]).filter_map do |t|
        text = t.is_a?(Hash) ? t["title"].to_s.squish : t.to_s.squish
        next if text.blank?

        { title: text.first(limit), why: t.is_a?(Hash) ? t["why"].to_s : "", length: [ text.length, limit ].min, trimmed: text.length > limit }
      end.uniq { |t| t[:title].downcase }.first(5)
    end
  end
end
