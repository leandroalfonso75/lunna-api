# Anúncios › "Quantidade de Vendas" (pedido do usuário em 25/11/2026): filtro abaixo de "Anúncios criados há mais de",
# cumulativo com ele, nas abas Todos e Catálogo. Pelo total vendido do anúncio desde a criação, como o Mercado Livre
# informa (ml_items.sold_quantity). `sales` = "none" (sem vendas) ou N (N vendas ou mais: 5, 10, 25, 50, 100, 500, 1000,
# 5000 ou o número do campo personalizado). Vazio ou inválido = sem filtro.
module Painel
  module SalesFilter
    MAX = 10_000_000

    # => :none, um inteiro (mínimo de vendas) ou nil
    def self.value(params)
      raw = params[:sales].to_s.strip
      return :none if raw == "none"
      return nil unless raw.match?(/\A\d+\z/)

      n = raw.to_i
      n.between?(1, MAX) ? n : nil
    end

    def self.apply(scope, params)
      case (v = value(params))
      when :none then scope.where(sold_quantity: [ 0, nil ])
      when Integer then scope.where("sold_quantity >= ?", v)
      else scope
      end
    end

    def self.label(params) = (v = value(params)) == :none ? "none" : v
  end
end
