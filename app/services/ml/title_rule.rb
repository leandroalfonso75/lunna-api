# Quando o Mercado Livre deixa trocar o título de um anúncio (conferido na documentação em 07/11/2026):
# - anúncio de catálogo: o título é o do produto do catálogo; não troca;
# - modelo User Products (tem family_name): o título é montado pelo ML a partir do family_name, que só pode ser
#   alterado se NENHUM anúncio do mesmo user product tiver venda (PUT /items/{id} com family_name);
# - modelo antigo: só sem venda (sold_quantity = 0), pelo PUT /items/{id} com title.
module Ml
  module TitleRule
    MAX_LENGTH = 60

    # up_sold: { user_product_id => vendas somadas dos anúncios do vendedor desse user product }
    def self.call(item, up_sold = {})
      return { editable: false, reason: "Os dados do anúncio ainda não foram carregados." } unless item
      return { editable: false, reason: "Anúncio de catálogo: o título é o do produto do catálogo e o Mercado Livre não deixa trocar." } if item.catalog_listing

      sold = item.user_product_id.present? ? [ up_sold[item.user_product_id].to_i, item.sold_quantity.to_i ].max : item.sold_quantity.to_i
      if sold.positive?
        return { editable: false, mode: mode(item),
                 reason: "O anúncio já tem #{sold} venda(s): o Mercado Livre só deixa trocar o título de anúncio sem vendas." }
      end

      { editable: true, mode: mode(item) }
    end

    def self.mode(item) = item.family_name.present? || item.user_product_id.present? ? "family_name" : "title"

    def self.up_sold(account)
      account.ml_items.where.not(user_product_id: nil).group(:user_product_id).sum(:sold_quantity)
    end
  end
end
