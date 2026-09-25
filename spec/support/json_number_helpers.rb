# BigDecimal vira string no JSON do Rails; o contrato (SPEC 10) quer números.
# `numeric_strings(json)` lista os caminhos com números serializados como texto.
module JsonNumberHelpers
  def numeric_strings(value, path = "")
    case value
    when Hash then value.flat_map { |key, child| numeric_strings(child, "#{path}.#{key}") }
    when Array then value.flat_map { |child| numeric_strings(child, "#{path}[]") }
    when String then value.match?(/\A-?\d+\.\d+\z/) ? [ path ] : []
    else []
    end.uniq
  end
end

RSpec.configure { |config| config.include JsonNumberHelpers, type: :request }
