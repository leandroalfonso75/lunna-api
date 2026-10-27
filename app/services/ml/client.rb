# Cliente HTTP só-leitura da API do Mercado Livre (SPEC 3). Recebe o
# access_token já válido de UMA conta — não renova token nem grava no banco
# (usado dentro de threads pela sincronização). 401 vira erro normal.
module Ml
  class Client
    class Error < StandardError
      attr_reader :status, :path

      def initialize(status:, path:, body: nil)
        @status = status
        @path = path
        detail = body.presence && " — #{body}"
        super("Ml::Client: #{status || "falha de conexão"} em #{path}#{detail}")
      end
    end

    class NotFound < Error; end

    BASE_URL = "https://api.mercadolibre.com"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    MAX_ATTEMPTS = 3
    BODY_EXCERPT_SIZE = 200

    # Campos do multiget (SPEC 3, item 5), na ordem exata da spec.
    ITEM_ATTRIBUTES = %w[
      id title status sub_status price original_price available_quantity sold_quantity
      listing_type_id category_id shipping catalog_listing permalink thumbnail
      seller_custom_field inventory_id attributes variations pictures video_id health date_created last_updated
    ].join(",")

    def initialize(access_token:, sleeper: ->(seconds) { sleep(seconds) })
      @access_token = access_token
      @sleeper = sleeper
    end

    def me
      get("/users/me")
    end

    def items_scan(seller_id, scroll_id: nil)
      params = { search_type: "scan", limit: 100 }
      params[:scroll_id] = scroll_id if scroll_id
      get("/users/#{seller_id}/items/search", params)
    end

    def items_multiget(ids)
      get("/items", ids: ids.join(","), attributes: ITEM_ATTRIBUTES)
    end

    # Estoque do Full (Fulfillment) de um inventory_id.
    def fulfillment_stock(inventory_id)
      get("/inventories/#{inventory_id}/stock/fulfillment")
    end

    def item_visits(item_id)
      get("/items/#{item_id}/visits/time_window", last: 60, unit: "day")
    end

    # field: :created (pedidos criados desde `from`) ou :updated (alterados desde `from`, inclusive os antigos).
    def orders_search(seller_id, from:, offset:, field: :created)
      get("/orders/search",
        seller: seller_id,
        "order.date_#{field == :updated ? "last_updated" : "created"}.from" => from.iso8601,
        sort: "date_desc",
        limit: 50,
        offset: offset)
    end

    # Central de Promoções: promoções da conta e ofertas de um anúncio (candidato, ativa, pendente).
    def seller_promotions(user_id)
      get("/seller-promotions/users/#{user_id}", app_version: "v2")
    end

    def item_promotions(item_id)
      get("/seller-promotions/items/#{item_id}", app_version: "v2")
    end

    # Reclamação/mediação de um pedido (cancelamento, reclamação, devolução).
    def claim(claim_id)
      get("/post-purchase/v1/claims/#{claim_id}")
    end

    def claim_reason(reason_id)
      get("/post-purchase/v1/claims/reasons/#{reason_id}")
    end

    # Devolução ligada à reclamação (404 quando não há).
    def claim_return(claim_id)
      get("/post-purchase/v2/claims/#{claim_id}/returns")
    end

    def shipment(shipment_id)
      get("/shipments/#{shipment_id}")
    end

    def shipment_costs(shipment_id)
      get("/shipments/#{shipment_id}/costs")
    end

    # Rota no singular (`/item/`, não `/items/`), como na SPEC.
    def item_performance(item_id)
      get("/item/#{item_id}/performance")
    end

    def item_description(item_id)
      get("/items/#{item_id}/description")
    end

    def category_attributes(category_id)
      get("/categories/#{category_id}/attributes")
    end

    def item_sale_price(item_id)
      get("/items/#{item_id}/sale_price", context: "channel_marketplace")
    end

    def listing_prices(price:, listing_type_id:, category_id:)
      get("/sites/MLB/listing_prices", price: price, listing_type_id: listing_type_id, category_id: category_id)
    end

    def shipping_free(seller_id, item_id:, free_shipping:, item_price:)
      get("/users/#{seller_id}/shipping_options/free",
        item_id: item_id, free_shipping: free_shipping, item_price: item_price, verbose: true)
    end

    def price_suggestion(item_id)
      get("/suggestions/items/#{item_id}/details")
    end

    # --- Publicidade (Product Ads) ---

    ADS_METRICS = %w[
      clicks prints ctr cpc cost cvr roas acos sov units_quantity total_amount direct_amount indirect_amount
      direct_units_quantity indirect_units_quantity organic_units_quantity organic_units_amount advertising_items_quantity
    ].join(",")

    def ads_advertisers
      get("/advertising/advertisers", { product_id: "PADS" }, { "api-version" => "1" })
    end

    def ads_campaigns(advertiser_id, from:, to:, offset: 0, limit: 50)
      get("/advertising/MLB/advertisers/#{advertiser_id}/product_ads/campaigns/search",
        { date_from: from.iso8601, date_to: to.iso8601, limit: limit, offset: offset, metrics: ADS_METRICS }, { "api-version" => "2" })
    end

    # Anúncios em campanha com as métricas do período; `daily: true` devolve uma linha por dia
    # (agregada, sem item) — usado com `campaign_id` para a série diária de cada campanha.
    def ads_items(advertiser_id, from:, to:, offset: 0, limit: 100, campaign_id: nil, daily: false)
      params = { date_from: from.iso8601, date_to: to.iso8601, limit: limit, offset: offset, metrics: ADS_METRICS }
      params["filters[campaign_id]"] = campaign_id if campaign_id
      params[:aggregation_type] = "DAILY" if daily
      get("/advertising/MLB/advertisers/#{advertiser_id}/product_ads/ads/search", params, { "api-version" => "2" })
    end

    private

    # `retry` só é válido dentro de um `rescue` — com dois motivos de repetir
    # (erro de conexão e status HTTP), o loop usa `next` pra tentar de novo.
    def get(path, params = {}, headers = {})
      attempt = 0

      loop do
        attempt += 1

        begin
          response = connection.get(path, params, headers)
        rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
          raise Error.new(status: nil, path: path, body: e.message) if attempt >= MAX_ATTEMPTS

          @sleeper.call(0.9 * attempt)
          next
        end

        return JSON.parse(response.body) if success?(response)
        raise_for(response, path) unless retryable?(response.status)

        if attempt < MAX_ATTEMPTS
          @sleeper.call(0.9 * attempt)
          next
        end

        raise_for(response, path)
      end
    end

    def success?(response)
      (200...300).cover?(response.status)
    end

    # 409 em leitura = "internal capacity constraints" (Central de Promoções sob carga): vale tentar de novo.
    def retryable?(status)
      status == 429 || status == 409 || status >= 500
    end

    def raise_for(response, path)
      klass = response.status == 404 ? NotFound : Error
      raise klass.new(status: response.status, path: path, body: short_body(response.body))
    end

    def short_body(body)
      body.to_s.byteslice(0, BODY_EXCERPT_SIZE)
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = READ_TIMEOUT
        f.headers["Authorization"] = "Bearer #{@access_token}"
        f.adapter Faraday.default_adapter
      end
    end
  end
end
