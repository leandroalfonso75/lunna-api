# Curva ABC > "Alterar modelo AGORA" (pedido do usuário em 14/11/2026, ajustado no mesmo dia): o campo Modelo da ficha
# técnica (até 110 caracteres) recebe as PALAVRAS-CHAVE MAIS BUSCADAS da categoria no Mercado Livre, exatamente como
# aparecem nas buscas (`/trends/MLB/{categoria}`), uma depois da outra. Regra do usuário: as duas primeiras não podem ter
# marca diferente da marca do anúncio (Gama, Philco, Taiff... só a partir da terceira num secador Mondial).
# A IA só escolhe quais buscas servem para este produto (e marca as que citam outra marca); a montagem é feita aqui, com
# os termos exatos. "Modelo detalhado": o modelo real do produto seguido de outros detalhes relevantes. Não publica nada.
module Ai
  class ModelKeywordSuggestions
    SYSTEM = <<~TXT.freeze
      Você ajuda a preencher o campo "Modelo" de um anúncio do Mercado Livre Brasil com as buscas mais feitas pelos
      compradores. Recebe a lista das buscas mais feitas na categoria (numeradas) e os dados do produto.
      1. "keywords": escolha da lista as buscas que um comprador DESTE produto faria (sirvam para este tipo de produto e
         suas características; deixe de fora buscas de outro tipo de produto, ex.: secador de parede para um secador de
         mão, ou de modelos específicos de outras marcas, ex.: "dyson airwrap"). Copie o texto EXATO da lista. Ordene da
         mais relevante para este produto para a menos relevante. Buscas de outra marca com o mesmo tipo de produto
         (ex.: "secador taiff", "secador gama", "secador philco" para um secador Mondial) SERVEM e devem entrar: quem busca
         a marca concorrente também é comprador. Em cada uma, "other_brand": true se a busca cita uma marca diferente da
         marca do anúncio.
      2. Se a lista vier vazia, em "keywords" escreva até 10 buscas curtas que os compradores costumam digitar para este
         produto no Mercado Livre (como se fossem da lista).
      3. "detailed_model": o modelo real do produto (código/linha, como está na ficha, no título ou na descrição) seguido
         de outros detalhes relevantes do produto (potência, voltagem, tecnologia, acessórios, cor...), só com dados
         da ficha/descrição (ex.: não escreva "bivolt" se a ficha não diz bivolt), sem palavras promocionais, até 255 caracteres. Ex.: "Power Shine Black SC-13 2000W Íon Turmalina
         com Difusor 127V ou 220V".
      Responda só com JSON: {"keywords": [{"keyword": "...", "other_brand": false}], "detailed_model": "..."}.
    TXT

    def self.call(company, info, description: nil, http: nil)
      limit = info[:max_length] || 110
      trends = Array(info[:trends])
      user = <<~TXT
        Título: #{info[:title]}
        Marca do anúncio: #{info[:brand].presence || '—'}
        Modelo atual: #{info[:model].presence || '—'} · Modelo detalhado atual: #{info[:detailed_model].presence || '—'}
        Ficha técnica: #{Array(info[:attributes]).join('; ')}
        Descrição (trecho): #{description.to_s.squish.first(1200).presence || '—'}
        Buscas mais feitas na categoria (da mais buscada para a menos):
        #{trends.each_with_index.map { |t, i| "#{i + 1}. #{t}" }.join("\n").presence || '(lista vazia)'}
      TXT
      data = Ai::JsonChat.call(company, system: SYSTEM, user: user, http: http)
      picked = pick(data["keywords"], trends, info[:brand])
      options = build_options(picked, trends, limit)
      detailed = data["detailed_model"].to_s.squish.first(255).presence || info[:detailed_model].presence || info[:model]
      { options: options, detailed_model: detailed, max_length: limit }
    end

    # => [{ keyword:, other_brand:, rank: (posição nas buscas, nil fora da lista) }], só termos da lista quando há lista
    def self.pick(raw, trends, brand)
      by_text = trends.each_with_index.to_h { |t, i| [ norm(t), [ t, i ] ] }
      own = norm(brand)
      Array(raw).filter_map do |k|
        text = (k.is_a?(Hash) ? k["keyword"] : k).to_s.squish
        next if text.blank?

        exact, rank = by_text[norm(text)]
        next if trends.any? && exact.nil? # a IA inventou ou alterou o termo: fica de fora
        keyword = exact || text.downcase
        other = k.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(k["other_brand"]) == true
        other = false if own.present? && norm(keyword).include?(own) # cita a marca do próprio anúncio
        { keyword: keyword, other_brand: other, rank: rank }
      end.uniq { |k| norm(k[:keyword]) }
    end

    # 3 montagens: pela relevância (ordem da IA), pela mais buscada (ordem do ML) e sem outras marcas.
    def self.build_options(picked, trends, limit)
      by_rank = picked.sort_by { |k| k[:rank] || 999 }
      [
        [ "Buscas mais ligadas a este produto primeiro", picked ],
        [ "Na ordem das mais buscadas da categoria", by_rank ],
        [ "Só buscas sem outras marcas", picked.reject { |k| k[:other_brand] } ]
      ].filter_map do |why, list|
        text = assemble(list, limit)
        next if text.blank?

        { model: text, why: why, length: text.length }
      end.uniq { |o| o[:model] }
    end

    # Junta as buscas (texto exato, separadas por espaço) até o limite; as duas primeiras sem marca de outra empresa.
    def self.assemble(list, limit)
      list = list.reject { |k| k[:other_brand] }.first(2) + (list - list.reject { |k| k[:other_brand] }.first(2))
      out = []
      list.each do |k|
        candidate = (out + [ k[:keyword] ]).join(" ")
        out << k[:keyword] if candidate.length <= limit
      end
      out.join(" ")
    end

    def self.norm(text) = I18n.transliterate(text.to_s).downcase.squish
  end
end
