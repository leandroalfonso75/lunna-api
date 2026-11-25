# Anúncios › "Quantidade de Vendas" (pedido do usuário em 25/11/2026): filtro abaixo de "Anúncios criados há mais de",
# cumulativo com ele, nas abas Todos e Catálogo. Pelo total vendido do anúncio desde a criação, como o Mercado Livre
# informa (ml_items.sold_quantity).
# `sales`:
#   "none"  → sem vendas
#   "A-B"   → de A a B vendas (faixas da tela: 1-4, 5-9, 10-24, 25-49, 50-99, 100-499, 500-999, 1000-4999, 5000-9999,
#             ou o personalizado de/até; revisto em 25/11/2026, antes eram "+N")
#   "A-"    → A vendas ou mais (personalizado sem o "até")
#   "N"     → N vendas ou mais (formato antigo, ainda aceito)
# Vazio, inválido ou faixa invertida = sem filtro.
module Painel
  module SalesFilter
    MAX = 10_000_000
    Range = Struct.new(:min, :max) # max nil = sem teto

    # => :none, um Range ou nil
    def self.value(params)
      raw = params[:sales].to_s.strip
      return :none if raw == "none"

      m = raw.match(/\A(\d+)(?:-(\d*))?\z/)
      return nil unless m

      min = m[1].to_i
      max = m[2].present? ? m[2].to_i : nil
      return nil if min > MAX || (max && (max > MAX || max < min)) || (min.zero? && max.nil?)

      Range.new(min, max)
    end

    def self.apply(scope, params)
      case (v = value(params))
      when :none then scope.where(sold_quantity: [ 0, nil ])
      when Range
        scope = scope.where("sold_quantity >= ?", v.min)
        v.max ? scope.where("sold_quantity <= ?", v.max) : scope
      else scope
      end
    end

    # um total de vendas passa no filtro? (sem filtro: sempre). Usado pelo anúncio pai (Painel::ListingFamilies)
    def self.match?(sold, params)
      case (v = value(params))
      when :none then sold.to_i.zero?
      when Range then sold.to_i >= v.min && (v.max.nil? || sold.to_i <= v.max)
      else true
      end
    end

    # valor normalizado devolvido pela API ("none", "A-B", "A-") ou nil
    def self.label(params)
      case (v = value(params))
      when :none then "none"
      when Range then "#{v.min}-#{v.max}"
      end
    end
  end
end
