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

    # ids dos anúncios da conta criados antes do corte (sem data de criação ficam de fora quando há filtro)
    def self.item_ids(account, params)
      cut = cutoff(params)
      cut && account.ml_items.where("date_created < ?", cut).select(:item_id)
    end
  end
end
