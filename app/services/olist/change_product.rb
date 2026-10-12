# Alterações no Olist ERP feitas pelo Lunna (preço e estoque). Toda alteração:
# - é validada antes de qualquer chamada;
# - é gravada em OlistChange ANTES (pending, com o valor anterior) e fechada
#   como done/failed depois — fica registrado quem, o quê, quando, antes e depois;
# - chama o Olist uma única vez (sem repetir sozinha);
# - atualiza a cópia local do produto quando o Olist aceita.
module Olist
  class ChangeProduct
    class Invalid < StandardError; end

    MAX_VALUE = 99_999_999

    def initialize(connection:, user:, product:, client: Olist::Client.new(connection))
      @connection = connection
      @user = user
      @product = product
      @client = client
    end

    def change_price(price:, promo_price: nil)
      price = decimal!(price, "preço", min: 0)
      promo = promo_price.nil? || promo_price == "" ? nil : decimal!(promo_price, "preço promocional", min: 0)

      perform(
        kind: "price",
        before: { price: @product.price&.to_f, promo_price: @product.promo_price&.to_f },
        request: { price: price.to_f, promo_price: promo&.to_f }.compact
      ) do
        response = @client.update_price(@product.olist_id, price: price.to_f, promo_price: promo&.to_f)
        @product.update!(price: price, promo_price: promo || @product.promo_price)
        response
      end
    end

    # type: B (balanço: define o saldo), E (entrada) ou S (saída).
    def change_stock(type:, quantity:, unit_price: nil, note: nil, deposit_id: nil)
      type = type.to_s.upcase
      raise Invalid, "Tipo de movimentação inválido (use B, E ou S)." unless Olist::Client::STOCK_TYPES.key?(type)

      quantity = decimal!(quantity, "quantidade", min: type == "B" ? 0 : 0.001)
      unit_price = decimal!(unit_price.presence || @product.avg_cost_price || 0, "preço unitário", min: 0)

      perform(
        kind: "stock",
        before: { balance: @product.stock_balance&.to_f, reserved: @product.stock_reserved&.to_f },
        request: { type: type, quantity: quantity.to_f, unit_price: unit_price.to_f, note: note.presence, deposit_id: deposit_id.presence }.compact
      ) do
        response = @client.post_stock(@product.olist_id, type: type, quantity: quantity.to_f, unit_price: unit_price.to_f,
          note: note, deposit_id: deposit_id)
        refresh_stock
        response
      end
    end

    private

    def perform(kind:, before:, request:)
      change = OlistChange.create!(
        company_id: @connection.company_id, user: @user, olist_product_id: @product.olist_id,
        kind: kind, before: before, request: request, status: "pending"
      )

      begin
        response = yield
        change.update!(status: "done", response: response.is_a?(Hash) ? response : {})
      rescue Olist::Client::Error, Olist::OAuth::Error => e
        change.update!(status: "failed", error: e.message.to_s.truncate(300))
        raise
      end

      change
    end

    # Depois de um lançamento, lê o saldo real no Olist (best effort: o lançamento já foi aceito).
    def refresh_stock
      data = @client.product_stock(@product.olist_id)
      @product.update!(
        stock_balance: data["saldo"], stock_reserved: data["reservado"], stock_available: data["disponivel"],
        stock_deposits: data["depositos"] || @product.stock_deposits
      )
    rescue Olist::Client::Error, Olist::OAuth::Error
      Rails.logger.warn("Olist::ChangeProduct: não foi possível reler o estoque após o lançamento")
    end

    def decimal!(value, label, min:)
      number = BigDecimal(value.to_s.tr(",", "."))
      raise Invalid, "O valor de #{label} é inválido." if number < min || number > MAX_VALUE

      number
    rescue ArgumentError, TypeError
      raise Invalid, "O valor de #{label} é inválido."
    end
  end
end
