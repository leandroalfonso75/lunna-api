# Contestação de reclamação com IA (pedido do usuário em 17/11/2026): o texto-modelo por grupo era genérico. Agora a IA lê
# o caso inteiro (relato do comprador, todas as mensagens em ordem, motivo, devolução, resolução, envio, provas do Lunna)
# e escreve uma defesa específica para o ML tirar a reclamação da reputação. Só usa fatos dos dados; não envia nada.
module Ai
  class ClaimContestDraft
    SYSTEM = <<~TXT.freeze
      Você é especialista em reputação de vendedores do Mercado Livre Brasil e escreve a contestação que o vendedor envia
      ao Mercado Livre pedindo que uma reclamação NÃO afete a reputação da conta.
      Antes de escrever, leia o caso inteiro: o relato do comprador (o que ele alegou, em detalhe), cada mensagem em ordem,
      o motivo, a solução proposta e aceita, a devolução (se o produto voltou, em que estado, se expirou), a resolução do
      ML, o tipo de envio (Full = armazenagem, separação, embalagem e transporte são do Mercado Livre) e as datas.
      Escolha o argumento mais forte e específico para ESTE caso, por exemplo (só se os fatos sustentarem):
      - o próprio ML decidiu a favor do vendedor, ou a resolução foi do depósito/logística do ML;
      - o comprador não devolveu o produto no prazo (devolução expirada/cancelada), sem comprovar o problema;
      - venda Full: dano, troca de item ou falta de peça ocorreram sob guarda e transporte do ML;
      - o relato descreve mau uso, uso fora das instruções, arrependimento ou expectativa diferente do anunciado, e não
        defeito do produto; o anúncio informa claramente o que o comprador diz não ter recebido;
      - defeito de fabricação coberto pela garantia do fabricante, sem culpa do vendedor;
      - o vendedor resolveu rápido e de forma completa (ofereceu devolução/reembolso no primeiro contato, prazos cumpridos),
        sem necessidade de intervenção;
      - divergência entre o que o comprador alegou e o que o produto devolvido mostrou.
      O argumento precisa combinar com o que o comprador relatou: se ele descreve defeito no uso (ex.: derreteu, parou de
      funcionar), não atribua a dano de transporte; prefira defeito coberto pela garantia do fabricante, a solução rápida
      dada pelo vendedor e o produto devolvido para conferência. Use o Full como argumento só para dano físico na entrega,
      item trocado ou peça faltando.
      Em "attach", liste provas concretas que o vendedor pode ter (nota fiscal, fotos do produto devolvido, print do
      anúncio com a informação que o comprador diz não ter recebido, comprovante de envio, conversa com o comprador).
      Regras: use só fatos presentes nos dados (datas, números, citações curtas do relato); não invente laudos, fotos, testes
      ou conversas; não acuse o comprador de má-fé; tom respeitoso e objetivo; português do Brasil; texto puro, sem
      markdown; 600 a 1.400 caracteres; comece com "Olá." e cite o número da reclamação e da venda; termine pedindo que a
      reclamação não seja considerada na reputação.
      Responda só com JSON:
      {"text": "a contestação", "argument": "o argumento principal em uma frase",
       "attach": ["provas que o vendedor deve anexar no ML, se tiver"], "weak_points": ["o que pode enfraquecer a defesa"]}
    TXT

    def self.call(company, facts, http: nil)
      data = Ai::JsonChat.call(company, system: SYSTEM, user: facts, http: http, max_tokens: 2500)
      text = data["text"].to_s.gsub("**", "").strip
      raise Ai::JsonChat::Error, "A IA não devolveu a contestação. Tente de novo." if text.blank?

      { text: text.first(3000), argument: data["argument"].to_s.squish.first(300),
        attach: Array(data["attach"]).map { |a| a.to_s.squish }.reject(&:blank?).first(6),
        weak_points: Array(data["weak_points"]).map { |a| a.to_s.squish }.reject(&:blank?).first(5) }
    end
  end
end
