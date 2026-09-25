# Gramática das expressões numéricas dos filtros de coluna (SPEC 10.4):
# operador (>, <, >=, <=, =, ou nada = igual), faixa (10-50 / 10 a 50 /
# 10 até 50, extremos em qualquer ordem) ou número BR solto.
module Painel
  class FilterExpression
    TOLERANCE = 1e-9
    OPERATOR_RE = /\A(>=|<=|>|<|=)/
    UNTIL_SPLIT_RE = /\A(.+?)até(.+)\z/i
    WORD_SPLIT_RE = /\A(.+?)a(.+)\z/i
    DASH_SPLIT_RE = /\A(\d[\d.,]*)-(\d[\d.,]*)\z/
    NUMBER_CHARS_RE = /\A-?[\d.,]+\z/
    THOUSANDS_RE = /\A\d{1,3}(\.\d{3})+\z/

    # nil (vazio) | {op:, value:} | {range: [min, max]} | :invalid
    def self.parse(raw)
      text = normalize(raw)
      return nil if text.empty?

      op_match = OPERATOR_RE.match(text)
      if op_match
        value = parse_number(text[op_match[0].length..])
        return :invalid if value.nil?

        return { op: op_match[1], value: value }
      end

      range = parse_range(text)
      return range if range

      value = parse_number(text)
      return :invalid if value.nil?

      { op: "=", value: value }
    end

    # Sempre exclui NULL (valor nulo nunca passa num filtro numérico).
    def self.apply(relation, column, parsed)
      relation.where.not(column => nil).where(*to_sql_condition(column, parsed))
    end

    # CAST no valor: colunas inteiras (stock, units_delta…) recebem o limite
    # fracionário da tolerância/faixa sem o Postgres tentar convertê-lo para integer.
    def self.to_sql_condition(column, parsed)
      return [ "#{column} BETWEEN CAST(? AS numeric) AND CAST(? AS numeric)", *parsed[:range] ] if parsed[:range]

      case parsed[:op]
      when "="  then [ "#{column} BETWEEN CAST(? AS numeric) AND CAST(? AS numeric)", parsed[:value] - TOLERANCE, parsed[:value] + TOLERANCE ]
      when ">=" then [ "#{column} >= CAST(? AS numeric)", parsed[:value] ]
      when "<=" then [ "#{column} <= CAST(? AS numeric)", parsed[:value] ]
      when ">"  then [ "#{column} > CAST(? AS numeric)", parsed[:value] ]
      when "<"  then [ "#{column} < CAST(? AS numeric)", parsed[:value] ]
      end
    end

    def self.normalize(raw)
      raw.to_s.gsub(/r\$/i, "").delete(" ").delete("%")
    end
    private_class_method :normalize

    def self.parse_range(text)
      match = UNTIL_SPLIT_RE.match(text) || WORD_SPLIT_RE.match(text) || DASH_SPLIT_RE.match(text)
      return nil unless match

      first = parse_number(match[1])
      second = parse_number(match[2])
      return :invalid if first.nil? || second.nil?

      { range: [ first, second ].sort }
    end
    private_class_method :parse_range

    # Número BR: com vírgula, pontos são milhar e a vírgula é decimal
    # (1.234,56 → 1234.56); sem vírgula, `\d{1,3}(\.\d{3})+` é milhar
    # (1.234 → 1234), senão ponto decimal (10.5).
    def self.parse_number(str)
      return nil if str.blank? || !NUMBER_CHARS_RE.match?(str)

      negative = str.start_with?("-")
      body = negative ? str[1..] : str
      return nil if body.empty?

      value =
        if body.count(",") > 1
          nil
        elsif body.include?(",")
          parse_comma_number(body)
        elsif THOUSANDS_RE.match?(body)
          Float(body.delete("."))
        else
          Float(body, exception: false)
        end

      return nil if value.nil?

      negative ? -value : value
    end
    private_class_method :parse_number

    def self.parse_comma_number(body)
      int_part, dec_part = body.split(",", 2)
      return nil if int_part.empty? || dec_part.empty? || !dec_part.match?(/\A\d+\z/)

      Float("#{int_part.delete('.')}.#{dec_part}", exception: false)
    end
    private_class_method :parse_comma_number
  end
end
