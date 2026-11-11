# Curva ABC > "Aplicar novo preço sugerido" e preço livre (pedido do usuário em 07/11/2026): muda o preço do anúncio no
# Mercado Livre (PUT /items/{id} com price). Escrita no ML: só admin, com confirmação, registrada em ml_item_edits.
# A partir de R$ 79 o ML passa a exigir frete grátis sozinho (o custo do frete do vendedor segue a tabela por faixa).
module Ml
  class ItemPrice
    MIN_PRICE = 1.0
    MAX_CHANGE = 0.6 # trava de segurança: mais de 60% de diferença do preço atual não passa
    Result = Struct.new(:ok, :message, :price, keyword_init: true)

    # free_shipping: true liga o frete grátis (cenário "Com frete grátis" no mesmo preço de hoje).
    def self.publish(client, account, item_id, price, user:, free_shipping: false) = new(client, account, item_id).publish(price, user, free_shipping)

    def initialize(client, account, item_id)
      @client = client
      @account = account
      @item_id = item_id
    end

    def publish(price, user, free_shipping = false)
      price = BigDecimal(price.to_s.tr(",", ".")).round(2).to_f rescue nil
      return Result.new(ok: false, message: "Informe um preço válido.") if price.nil? || price < MIN_PRICE

      item = @client.item_full(@item_id)
      current = item["price"].to_f
      same = (current - price).abs < 0.005
      return Result.new(ok: false, message: "O anúncio já está com esse preço.") if same && !free_shipping
      if free_shipping && item.dig("shipping", "free_shipping")
        return Result.new(ok: false, message: "O anúncio já oferece frete grátis.") if same
      end
      if current.positive? && (price - current).abs / current > MAX_CHANGE
        return Result.new(ok: false, message: "Mudança grande demais (#{((price - current) / current * 100).round}% do preço atual). Confira o valor ou altere no Mercado Livre.")
      end

      body = {}
      body[:price] = price unless same
      body[:shipping] = { free_shipping: true } if free_shipping
      edit = @account.ml_item_edits.create!(item_id: @item_id, user: user, kind: free_shipping ? "preco_frete_gratis" : "preco",
                                            before: { price: current, free_shipping: item.dig("shipping", "free_shipping") }, after: body)
      @client.update_item(@item_id, body)
      edit.update!(ok: true)
      AbcSuggestionAck.hold_price!(@account, @item_id, kind: "aplicada", user: user) # preço em maturação por 15 dias
      @account.ml_items.where(item_id: @item_id).update_all(free_shipping ? { price: price, free_shipping: true } : { price: price })
      @account.item_metrics.where(item_id: @item_id).update_all(price: price)
      note = price >= 79 && current < 79 ? " A partir de R$ 79 o Mercado Livre passa a oferecer frete grátis (você paga o frete da faixa)." : ""
      text = same ? "Frete grátis ligado no Mercado Livre (preço mantido em R$ #{format('%.2f', price).tr('.', ',')})." :
                    "Preço alterado no Mercado Livre: R$ #{format('%.2f', price).tr('.', ',')}#{free_shipping ? ', com frete grátis' : ''}.#{note}"
      Result.new(ok: true, price: price, message: text)
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(500))
      Result.new(ok: false, message: "O Mercado Livre recusou o novo preço: #{e.message.to_s.first(220)}")
    end
  end
end
