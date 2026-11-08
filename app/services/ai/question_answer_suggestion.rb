# Seção Perguntas > "Sugerir resposta" (pedido do usuário em 08/11/2026): a IA escreve uma resposta a partir dos dados
# do anúncio (título, ficha técnica, descrição, preço, estoque, frete) e das respostas já dadas no mesmo anúncio e nos
# outros anúncios do mesmo SKU, no tom da loja. Só sugere: o usuário revisa e envia.
module Ai
  class QuestionAnswerSuggestion
    MAX = 2000
    SYSTEM = <<~TXT.freeze
      Você responde perguntas de compradores no Mercado Livre Brasil em nome da loja. Regras:
      - Responda só com o que os dados do anúncio, as FOTOS do anúncio (anexadas) ou as respostas anteriores da loja
        confirmam. Use as fotos para cor, tom, tamanho, formato, conteúdo da embalagem e comparações (ex.: dois tons lado a
        lado: diga qual é mais claro/escuro). Se não der para afirmar, não invente: diga que vai confirmar.
      - Tons de maquiagem: compare as cores das amostras na foto (claridade e subtom: rosado, neutro, amarelado). Em linhas
        de base, o número do tom costuma subir do mais claro para o mais escuro: use isso para conferir o que vê na foto.
        Se a diferença for sutil, diga que é sutil e explique o subtom. Lembre que as cores podem variar conforme a tela.
      - Use o mesmo tom, cumprimento e assinatura das respostas anteriores da loja (se houver).
      - Proibido pelo ML: telefone, e-mail, links externos, redes sociais, pedir para comprar fora do ML.
      - Seja direto e cordial, em português do Brasil, no máximo 600 caracteres.
      Responda só com JSON: {"answer": "texto", "sources": ["de onde veio cada informação, curto"], "confidence": "alta|media|baixa"}
    TXT

    def self.call(company, question:, item:, description:, same_item:, same_sku:, attributes:, tone: [], pictures: [], http: nil)
      history = ->(list) { list.map { |q| "P: #{q.text.to_s.squish}\nR: #{q.answer_text.to_s.squish}" }.join("\n\n").presence || "—" }
      user = <<~TXT
        Pergunta do comprador: #{question.text}

        Anúncio: #{item&.title} (#{question.item_id})
        Preço: #{item&.price ? format('R$ %.2f', item.price).tr('.', ',') : '—'} · Estoque: #{item&.available_quantity || '—'} · Frete grátis: #{item&.free_shipping ? 'sim' : 'não'} · Full: #{item&.logistic_type == 'fulfillment' ? 'sim' : 'não'}
        Ficha técnica: #{attributes.presence || '—'}
        Descrição (trecho): #{description.to_s.squish.first(2500).presence || '—'}

        Respostas anteriores da loja neste anúncio:
        #{history.call(same_item)}

        Respostas da loja em outros anúncios do mesmo SKU:
        #{history.call(same_sku)}

        Exemplos recentes de respostas da loja (só para copiar o tom, cumprimento e assinatura):
        #{tone.map { |q| q.answer_text.to_s.squish }.join("\n").presence || '—'}
      TXT
      data = Ai::JsonChat.call(company, system: SYSTEM, user: user, http: http, max_tokens: 1200, images: pictures)
      answer = data["answer"].to_s.strip
      raise Ai::JsonChat::Error, "A IA não devolveu uma resposta. Tente de novo." if answer.blank?

      { answer: answer.first(MAX), sources: Array(data["sources"]).map(&:to_s).first(5), confidence: data["confidence"].to_s.presence }
    end
  end
end
