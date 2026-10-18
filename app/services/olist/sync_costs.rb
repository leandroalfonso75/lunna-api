# Lê as movimentações de estoque do Olist (Suprimentos > Controle de Estoque) e calcula
# o custo PEPS de cada produto. Roda em lotes: produtos nunca lidos primeiro, depois os
# cujo saldo mudou desde o último cálculo ou que não são relidos há mais de 1 dia.
# Sem permissão no Olist (403), registra isso na conexão e tenta de novo só a cada 30 min.
module Olist
  class SyncCosts
    BATCH = 40
    RECHECK = 1.day
    FORBIDDEN_RETRY = 30.minutes

    def initialize(connection, client: Olist::Client.new(connection))
      @connection = connection
      @client = client
    end

    def call
      return if throttled?

      products = candidates.to_a
      failed = false

      products.each do |product|
        sync_product(product)
      rescue Olist::Client::Forbidden
        return @connection.update!(costs_status: "forbidden", costs_checked_at: Time.current)
      rescue Olist::Client::Error, Olist::OAuth::Error => e
        Rails.logger.warn("Olist::SyncCosts: produto #{product.olist_id} (#{e.class})")
        failed = true
      end

      @connection.update!(costs_status: failed ? "error" : "ok", costs_checked_at: Time.current)
    end

    private

    def throttled?
      @connection.costs_status == "forbidden" && @connection.costs_checked_at.present? &&
        @connection.costs_checked_at > FORBIDDEN_RETRY.ago
    end

    def candidates
      OlistProduct.where(company_id: @connection.company_id).where.not(variation_kind: "P").where.not(status: "E")
        .where("movements_synced_at IS NULL OR movements_synced_at < ? OR fifo_balance_at_calc IS DISTINCT FROM stock_balance", RECHECK.ago)
        .order(Arel.sql("movements_synced_at ASC NULLS FIRST")).limit(BATCH)
    end

    def sync_product(product)
      items = @client.all_stock_movements(product.olist_id)
      now = Time.current
      rows = items.filter_map { |item| row_for(product, item, now) }

      OlistStockMovement.transaction do
        OlistStockMovement.where(company_id: product.company_id, olist_product_id: product.olist_id).delete_all
        OlistStockMovement.insert_all(rows) if rows.any?
      end

      calculate(product, now)
    end

    # Recalcula o PEPS de um produto a partir das movimentações já guardadas (sem chamar o Olist).
    # Útil quando a regra de cálculo muda.
    def recalculate(product)
      calculate(product, Time.current)
    end

    public :recalculate

    def calculate(product, now)
      movements = OlistStockMovement.where(company_id: product.company_id, olist_product_id: product.olist_id).map do |m|
        { id: m.movement_id, deposit_id: m.deposit_id, kind: m.kind, quantity: m.quantity, price: m.price,
          moved_at: m.moved_at, origin: m.origin, note: m.note }
      end
      ledger = ledger_deposits(product)
      stock, complete = current_stock(product, movements, ledger)
      result = Olist::Fifo.call(movements, ledger_deposit_ids: ledger, current_stock: stock, stock_complete: complete)
      store(product, result, now)
    end

    # Estoque real da empresa: saldo do Olist + Full do Mercado Livre (mesma soma da tela Produtos).
    # => [estoque, completo?]. Completo quando o Full foi lido ou o produto não tem movimento no depósito do Full.
    def current_stock(product, movements, ledger)
      full = Olist::FullStock.for_skus(@connection.company, [ product.sku ])[product.sku]
      uses_full = movements.any? { |m| ledger.include?(m[:deposit_id]) }
      [ product.stock_balance.to_f + full&.total.to_f, full.present? || !uses_full ]
    end

    def row_for(product, item, now)
      return nil if item["id"].blank? || OlistStockMovement::KINDS.exclude?(item["tipo"])

      {
        company_id: product.company_id, olist_product_id: product.olist_id, movement_id: item["id"], deposit_id: item["idDeposito"],
        kind: item["tipo"], quantity: item["quantidade"] || 0, price: item["preco"], moved_at: parse_time(item["data"]),
        origin: item["origem"], note: item["observacao"].to_s.truncate(255), created_at: now, updated_at: now
      }
    end

    # Depósitos que o Olist não conta no saldo (Full ML): só as saídas (vendas) são registradas ali.
    def ledger_deposits(product)
      (product.stock_deposits || []).select { |deposit| deposit["desconsiderar"] }.filter_map { |deposit| deposit["id"] }
    end

    def store(product, result, now)
      product.update!(
        fifo_unit_cost: result.unit_cost, fifo_last_entry_cost: result.last_entry_cost, fifo_stock_value: result.stock_value, fifo_units: result.units,
        fifo_units_without_cost: result.units_without_cost, fifo_shortfall: result.shortfall,
        fifo_layers: result.layers.map { |layer| layer_json(layer) },
        fifo_balance_at_calc: product.stock_balance, fifo_calculated_at: now, movements_synced_at: now
      )
    end

    def layer_json(layer)
      { moved_at: layer.moved_at, quantity: layer.quantity.to_f, remaining: layer.remaining.to_f,
        unit_cost: layer.unit_cost&.to_f, origin: layer.origin }
    end

    # O Olist devolve "aaaa-mm-dd hh:mm:ss" no horário de Brasília.
    def parse_time(value)
      return nil if value.blank?

      ActiveSupport::TimeZone["America/Sao_Paulo"].parse(value)
    end
  end
end
