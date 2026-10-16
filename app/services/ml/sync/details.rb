# Etapa 6 (SPEC 4): cadastro e preço dos anúncios active/paused/under_review
# vencidos (o Run seleciona o lote a partir de details_checked_at). 4
# threads. Cada anúncio faz vários sub-chamados independentes (descrição,
# sale_price, tarifa/frete no preço efetivo, referência de preço e,
# condicionalmente, tarifa/frete no preço sugerido); erro de UM sub-chamado
# vira nota e os demais campos seguem — só o carimbo details_checked_at é
# sempre gravado. `update_all` por item (não upsert).
module Ml
  module Sync
    module Details
      THREADS = 4
      MAX_NAMES = 15
      FREE_SHIPPING_FLOOR = 79
      PRICE_EPSILON = 0.009

      Result = Struct.new(:notes, keyword_init: true)

      # Sentinela devolvida por `safe` quando o sub-chamado falhou — nunca é
      # um valor de negócio de verdade, só um marcador pra "não grava esse campo".
      FAILED = Object.new.freeze
      private_constant :FAILED

      def self.call(client, account, items)
        category_attrs = fetch_category_attrs(client, items)

        results = Ml::Sync::Parallel.map(items, threads: THREADS) do |item|
          process(client, account, item, category_attrs[item.category_id])
        end

        notes = []
        results.each_with_index do |(status, value), i|
          item = items[i]

          if status == :ok
            attrs, item_notes = value
            MlItem.where(item_id: item.item_id).update_all(attrs)
            notes.concat(item_notes)
          else
            MlItem.where(item_id: item.item_id).update_all(details_checked_at: Time.current)
            notes << "cadastro #{item.item_id}: #{value.message}"
          end
        end

        Result.new(notes: notes)
      end

      def self.fetch_category_attrs(client, items)
        items.filter_map(&:category_id).uniq.index_with do |category_id|
          client.category_attributes(category_id)
        rescue Ml::Client::Error
          []
        end
      end
      private_class_method :fetch_category_attrs

      def self.process(client, account, item, category_attributes)
        notes = []
        attrs = { details_checked_at: Time.current }

        description_len = safe(notes, item.item_id, "descrição") { fetch_description_len(client, item) }
        attrs[:description_len] = description_len unless description_len == FAILED

        sale_price, regular_price = fetch_sale_price_pair(client, item, notes)
        attrs[:sale_price] = sale_price unless sale_price == FAILED
        attrs[:regular_price] = regular_price unless regular_price == FAILED
        effective_price = (sale_price != FAILED && sale_price.present? && sale_price > 0) ? sale_price : item.price

        fee = safe(notes, item.item_id, "tarifa") { fetch_fee(client, item, effective_price) }
        unless fee == FAILED
          attrs[:fee_now] = fee["sale_fee_amount"]
          attrs[:fee_details] = fee["sale_fee_details"]
        end

        ship_cost = safe(notes, item.item_id, "frete") { fetch_ship_cost(client, account, item, effective_price, item.free_shipping) }
        attrs[:ship_cost] = ship_cost unless ship_cost == FAILED

        missing_required, missing_main = missing_attrs(category_attributes, item.attrs_filled)
        attrs[:attrs_missing_required] = missing_required
        attrs[:attrs_missing_main] = missing_main

        price_ref = safe(notes, item.item_id, "referência de preço") { fetch_price_ref(client, item) }
        attrs[:price_ref] = price_ref unless price_ref == FAILED

        # Referência que falhou nesta rodada: mantém price_ref, fee_at_ref e ship_at_ref da
        # última coleta boa (até a próxima rodada de 12 h) em vez de zerar os valores no sugerido.
        unless price_ref == FAILED
          attrs[:fee_at_ref], attrs[:ship_at_ref] = ref_fees(client, account, item, effective_price, price_ref, notes)
        end

        [ attrs, notes ]
      end
      private_class_method :process

      def self.fetch_sale_price_pair(client, item, notes)
        pair = safe(notes, item.item_id, "sale_price") { fetch_sale_price(client, item) }
        pair == FAILED ? [ FAILED, FAILED ] : pair
      end
      private_class_method :fetch_sale_price_pair

      def self.fetch_description_len(client, item)
        client.item_description(item.item_id)["plain_text"].to_s.length
      rescue Ml::Client::NotFound
        0
      end
      private_class_method :fetch_description_len

      def self.fetch_sale_price(client, item)
        data = client.item_sale_price(item.item_id)
        amount = data["amount"]
        [ amount.present? && amount > 0 ? amount : nil, data["regular_amount"] ]
      end
      private_class_method :fetch_sale_price

      def self.fetch_fee(client, item, price)
        client.listing_prices(price: price, listing_type_id: item.listing_type_id, category_id: item.category_id)
      end
      private_class_method :fetch_fee

      def self.fetch_ship_cost(client, account, item, price, free_shipping)
        data = client.shipping_free(account.seller_id, item_id: item.item_id, free_shipping: free_shipping, item_price: price)
        data.dig("coverage", "all_country", "list_cost")
      end
      private_class_method :fetch_ship_cost

      def self.fetch_price_ref(client, item)
        data = client.price_suggestion(item.item_id)
        {
          status: data["status"],
          current: data.dig("current_price", "amount"),
          suggested: data.dig("suggested_price", "amount"),
          lowest: data.dig("lowest_price", "amount"),
          internal: data.dig("internal_price", "amount"),
          pct: data["percent_difference"],
          applicable: data["applicable_suggestion"],
          selling_fees: data.dig("costs", "selling_fees"),
          shipping_fees: data.dig("costs", "shipping_fees"),
          compared: data["compared_values"],
          graph: graph_from(data),
          updated: data["last_updated"]
        }
      rescue Ml::Client::NotFound
        nil
      end
      private_class_method :fetch_price_ref

      def self.graph_from(data)
        (data.dig("metadata", "graph") || []).first(8).map do |entry|
          { p: entry.dig("price", "amount"), t: entry.dig("info", "title"), s: entry.dig("info", "sold_quantity") }
        end
      end
      private_class_method :graph_from

      # Tarifa/frete no preço sugerido: só quando o sugerido é > 0 e difere
      # do efetivo em mais de R$ 0,009; senão ambos nil (sempre atribuídos,
      # nunca "pulados" como os demais campos desta etapa).
      def self.ref_fees(client, account, item, effective_price, price_ref, notes)
        suggested = price_ref && price_ref[:suggested]
        return [ nil, nil ] unless suggested.present? && suggested > 0 && (suggested.to_f - effective_price.to_f).abs > PRICE_EPSILON

        fee = safe(notes, item.item_id, "tarifa_ref") { fetch_fee(client, item, suggested)["sale_fee_amount"] }
        free_shipping_ref = suggested >= FREE_SHIPPING_FLOOR ? true : item.free_shipping
        ship = safe(notes, item.item_id, "frete_ref") { fetch_ship_cost(client, account, item, suggested, free_shipping_ref) }

        [ fee == FAILED ? nil : fee, ship == FAILED ? nil : ship ]
      end
      private_class_method :ref_fees

      # Faltando = id não está em attrs_filled. Obrigatório = tag required
      # ou catalog_required. Principal = relevance == 1 e não obrigatório.
      # Exclui SELLER_SKU e tags read_only/hidden/fixed. Até 15 nomes cada.
      def self.missing_attrs(category_attributes, attrs_filled)
        filled = (attrs_filled || []).to_set
        relevant = (category_attributes || []).reject { |a| excluded?(a) }

        required = relevant.select { |a| required?(a) }
        main = relevant.select { |a| !required?(a) && a["relevance"] == 1 }

        [ names_missing(required, filled), names_missing(main, filled) ]
      end
      private_class_method :missing_attrs

      def self.excluded?(attribute)
        tags = attribute["tags"] || {}
        attribute["id"] == "SELLER_SKU" || tags["read_only"] || tags["hidden"] || tags["fixed"]
      end
      private_class_method :excluded?

      def self.required?(attribute)
        tags = attribute["tags"] || {}
        !!(tags["required"] || tags["catalog_required"])
      end
      private_class_method :required?

      def self.names_missing(list, filled)
        list.reject { |a| filled.include?(a["id"]) }.map { |a| a["name"] }.first(MAX_NAMES)
      end
      private_class_method :names_missing

      def self.safe(notes, item_id, label)
        yield
      rescue Ml::Client::Error => e
        notes << "#{label} #{item_id}: #{e.message}"
        FAILED
      end
      private_class_method :safe
    end
  end
end
