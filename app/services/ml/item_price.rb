# Curva ABC > "Aplicar novo preço sugerido" e preço livre (pedido do usuário em 07/11/2026): muda o preço do anúncio no
# Mercado Livre (PUT /items/{id} com price). Escrita no ML: só admin, com confirmação, registrada em ml_item_edits.
# A partir de R$ 79 o ML passa a exigir frete grátis sozinho (o custo do frete do vendedor segue a tabela por faixa).
module Ml
  class ItemPrice
    MIN_PRICE = 1.0
    MAX_CHANGE = 0.6 # trava de segurança: mais de 60% de diferença do preço atual não passa
    Result = Struct.new(:ok, :message, :price, keyword_init: true)

    def self.publish(client, account, item_id, price, user:) = new(client, account, item_id).publish(price, user)

    def initialize(client, account, item_id)
      @client = client
      @account = account
      @item_id = item_id
    end

    def publish(price, user)
      price = BigDecimal(price.to_s.tr(",", ".")).round(2).to_f rescue nil
      return Result.new(ok: false, message: "Informe um preço válido.") if price.nil? || price < MIN_PRICE

      item = @client.item_full(@item_id)
      current = item["price"].to_f
      return Result.new(ok: false, message: "O anúncio já está com esse preço.") if (current - price).abs < 0.005
      if current.positive? && (price - current).abs / current > MAX_CHANGE
        return Result.new(ok: false, message: "Mudança grande demais (#{((price - current) / current * 100).round}% do preço atual). Confira o valor ou altere no Mercado Livre.")
      end

      edit = @account.ml_item_edits.create!(item_id: @item_id, user: user, kind: "preco", before: { price: current }, after: { price: price })
      @client.update_item(@item_id, { price: price })
      edit.update!(ok: true)
      @account.ml_items.where(item_id: @item_id).update_all(price: price)
      @account.item_metrics.where(item_id: @item_id).update_all(price: price)
      note = price >= 79 && current < 79 ? " A partir de R$ 79 o Mercado Livre passa a oferecer frete grátis (você paga o frete da faixa)." : ""
      Result.new(ok: true, price: price, message: "Preço alterado no Mercado Livre: R$ #{format('%.2f', price).tr('.', ',')}.#{note}")
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(500))
      Result.new(ok: false, message: "O Mercado Livre recusou o novo preço: #{e.message.to_s.first(220)}")
    end
  end
end
