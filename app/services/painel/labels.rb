# Rótulos e links de anúncio usados por várias respostas (tabela, Curva ABC,
# detalhe) — um lugar só para os textos da SPEC 6 e 7.7.
module Painel
  module Labels
    STATUS = {
      "active" => "Ativo",
      "paused" => "Pausado",
      "closed" => "Finalizado",
      "under_review" => "Em revisão",
      "inactive" => "Inativo"
    }.freeze

    LISTING_TYPE = { "P" => "Premium", "C" => "Clássico" }.freeze

    module_function

    def status(value) = STATUS.fetch(value.to_s, value.to_s.humanize.presence)

    # "P" / "C" (item_metrics.listing_type) ou gold_pro / gold_special (ml_items).
    def listing_type(value)
      key = { "gold_pro" => "P", "gold_special" => "C" }.fetch(value.to_s, value.to_s)
      LISTING_TYPE[key]
    end

    def links(item_id)
      number = item_id.to_s.delete_prefix("MLB")
      {
        public: "https://produto.mercadolivre.com.br/MLB-#{number}",
        seller_panel: "https://www.mercadolivre.com.br/anuncios/lista?search=#{item_id}"
      }
    end
  end
end
