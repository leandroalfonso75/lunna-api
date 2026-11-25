# Anúncios › "Anúncios criados há mais de N dias" (pedido do usuário em 24/11/2026): filtro acima das abas Todos e
# Catálogo, por ml_items.date_created. `created_older_than` = dias (30, 60, 90, 180, 365 ou qualquer número inteiro do
# campo personalizado). Vazio, zero ou inválido = sem filtro.
module Painel
  module CreatedFilter
    MAX_DAYS = 36_500

    def self.days(params)
      raw = params[:created_older_than].to_s.strip
      return nil unless raw.match?(/\A\d+\z/)

      days = raw.to_i
      days.between?(1, MAX_DAYS) ? days : nil
    end

    def self.cutoff(params)
      (d = days(params)) ? d.days.ago : nil
    end

    # sem data de criação fica de fora quando há filtro
    def self.apply(scope, params)
      (cut = cutoff(params)) ? scope.where("date_created < ?", cut) : scope
    end
  end
end
