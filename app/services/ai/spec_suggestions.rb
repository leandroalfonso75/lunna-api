# Curva ABC > "Sugerir características": preenche os campos que faltam na ficha técnica a partir do anúncio (título,
# características já preenchidas e descrição). Só sugere o que dá para afirmar pelos dados; nas listas, escolhe um
# dos valores permitidos. Não publica nada.
module Ai
  class SpecSuggestions
    SYSTEM = <<~TXT.freeze
      Você preenche a ficha técnica de anúncios do Mercado Livre Brasil. Para cada campo pedido, sugira o valor SÓ quando
      ele puder ser afirmado pelos dados do anúncio (título, características já preenchidas, descrição) ou for
      conhecimento seguro sobre esse produto específico (marca + modelo). Se não tiver segurança, não sugira o campo.
      Quando o campo tiver lista de valores permitidos, use exatamente um deles (devolva o id). Campo com vários valores
      (multivalorado): devolva os valores em value_name separados por vírgula e value_id null. Campos numéricos com
      unidade: "número unidade" (ex.: "25 cm"), usando uma das unidades permitidas.
      Responda só com JSON: {"values": {"ID_DO_CAMPO": {"value_id": "id ou null", "value_name": "texto", "why": "fonte curta"}}}
    TXT

    def self.call(company, info, description: nil, http: nil)
      fields = info[:fields].map do |f|
        allowed = f[:values].any? ? " valores permitidos: #{f[:values].first(120).map { |v| "#{v[:id]}=#{v[:name]}" }.join(' | ')}" : ""
        units = f[:units].any? ? " unidades: #{f[:units].map { |u| u[:id] }.join(', ')}" : ""
        "- #{f[:id]} (#{f[:name]}, tipo #{f[:value_type]}#{f[:multivalued] ? ', multivalorado' : ''})#{allowed}#{units}"
      end
      user = <<~TXT
        Título: #{info[:title]}
        Características já preenchidas: #{info[:filled].map { |a| "#{a[:name]}: #{a[:value]}" }.join('; ')}
        Descrição (trecho): #{description.to_s.squish.first(2500).presence || '—'}
        Campos a preencher:
        #{fields.join("\n")}
      TXT
      data = Ai::JsonChat.call(company, system: SYSTEM, user: user, http: http, max_tokens: 3000)
      by_id = info[:fields].index_by { |f| f[:id] }
      data["values"].to_h.filter_map do |id, v|
        f = by_id[id]
        next unless f && v.is_a?(Hash)

        # campo com vários valores: a IA pode devolver uma lista; o ML aceita os valores separados por vírgula
        if v["value_name"].is_a?(Array) || v["value_id"].is_a?(Array)
          names = Array(v["value_name"]).map(&:to_s).map(&:strip).reject(&:blank?)
          names = Array(v["value_id"]).filter_map { |vid| f[:values].find { |x| x[:id].to_s == vid.to_s }&.dig(:name) } if names.empty?
          next if names.empty?

          next [ id, { value_id: nil, value_name: names.uniq.join(", "), why: v["why"].to_s } ]
        end

        if f[:values].any?
          match = f[:values].find { |x| x[:id].to_s == v["value_id"].to_s } ||
                  f[:values].find { |x| x[:name].to_s.casecmp?(v["value_name"].to_s.strip) }
          next if match.nil? && !f[:free_text]

          value = match ? { value_id: match[:id].to_s, value_name: match[:name] } : { value_id: nil, value_name: v["value_name"].to_s.strip }
        else
          next if v["value_name"].to_s.strip.blank?

          value = { value_id: nil, value_name: v["value_name"].to_s.strip }
        end
        [ id, value.merge(why: v["why"].to_s) ]
      end.to_h
    end
  end
end
