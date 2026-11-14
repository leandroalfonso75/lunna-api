# Curva ABC > "Alterar descrição AGORA" (pedido do usuário em 14/11/2026): reescreve a descrição do anúncio de forma mais
# chamativa e persuasiva, com base no título, na ficha, na descrição atual e nas perguntas dos compradores. Texto puro
# (o Mercado Livre não aceita HTML), sem contato, links, preço ou promessas que não estão nos dados. Não publica nada.
module Ai
  class DescriptionSuggestion
    SYSTEM = <<~TXT.freeze
      Você é redator de anúncios do Mercado Livre Brasil, especialista em conversão. Reescreva a descrição do produto para
      convencer quem chegou ao anúncio a comprar, e para ajudar na busca. Estrutura:
      1. Abertura de 1 a 2 frases com o principal benefício (o problema que o produto resolve).
      2. Benefícios e diferenciais em tópicos curtos (cada linha começando com "- ").
      3. Como usar / para quem é indicado.
      4. Especificações técnicas (só as que estão nos dados).
      5. O que vem na embalagem (se estiver nos dados).
      6. Perguntas frequentes curtas, respondendo às dúvidas reais dos compradores (quando houver perguntas).
      Regras do Mercado Livre: texto puro, sem HTML, sem emojis, sem links, telefone, e-mail, redes sociais ou menção a
      outros sites; sem preço, frete, promoção ou condições de pagamento; não invente características, garantias,
      certificações ou medidas que não estão nos dados. Use as palavras que o comprador busca de forma natural.
      Se a ficha técnica e a descrição atual discordarem (ex.: potência), use o valor da ficha técnica, NÃO comente a
      diferença no texto e avise em "highlights" começando com "Conferir:". Nas perguntas frequentes, responda só o que
      os dados confirmam (nada de "geralmente" ou suposições); sem confirmação, deixe a pergunta de fora.
      Títulos de seção em MAIÚSCULAS numa linha própria, linhas em branco entre as seções; entre 1.200 e 3.500 caracteres.
      Responda só com JSON: {"text": "a descrição completa", "highlights": ["o que melhorou, em frases curtas"]}.
    TXT

    MAX = 50_000

    def self.call(company, info, current:, questions: [], http: nil)
      user = <<~TXT
        Título: #{info[:title]}
        Marca: #{info[:brand].presence || '—'} · Modelo: #{info[:model].presence || '—'}
        Ficha técnica: #{Array(info[:attributes]).join('; ')}
        Perguntas dos compradores: #{Array(questions).first(15).join(' | ').presence || '—'}
        Descrição atual:
        #{current.to_s.strip.first(6000).presence || '(sem descrição)'}
      TXT
      data = Ai::JsonChat.call(company, system: SYSTEM, user: user, http: http, max_tokens: 4000)
      text = clean(data["text"].to_s)
      raise Ai::JsonChat::Error, "A IA não devolveu uma descrição. Tente de novo." if text.blank?

      { text: text, highlights: Array(data["highlights"]).map(&:to_s).first(6), length: text.length }
    end

    # tira HTML, emojis e excesso de linhas em branco (o ML recusa ou mostra mal)
    def self.clean(text)
      text = text.gsub(/<[^>]+>/, "").gsub(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/, "")
      text.gsub(/\r\n?/, "\n").gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip.first(MAX)
    end
  end
end
