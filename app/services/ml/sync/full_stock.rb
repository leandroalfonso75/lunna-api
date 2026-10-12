# Etapa de estoque do Full: para os anúncios Full (logistic_type fulfillment)
# lê o estoque de cada inventory_id direto no Mercado Livre
# (GET /inventories/{id}/stock/fulfillment) e grava em ml_full_stocks. 4 threads;
# um inventory_id compartilhado por vários anúncios é lido uma vez só. Erro de um
# inventory vira nota e os demais seguem. Lote limitado, os mais antigos primeiro.
module Ml
  module Sync
    module FullStock
      THREADS = 4
      BATCH = 300

      Result = Struct.new(:notes, :count, keyword_init: true)

      def self.call(client, account)
        ids = inventory_ids(account)
        return Result.new(notes: [], count: 0) if ids.empty?

        known = MlFullStock.where(ml_account_id: account.id, inventory_id: ids).pluck(:inventory_id, :synced_at).to_h
        ids = ids.sort_by { |id| known[id] || Time.zone.at(0) }.first(BATCH)

        notes = []
        rows = []
        results = Ml::Sync::Parallel.map(ids, threads: THREADS) { |id| client.fulfillment_stock(id) }

        results.each_with_index do |(status, value), i|
          if status == :ok
            rows << row_for(account, ids[i], value)
          else
            notes << "estoque Full #{ids[i]}: #{value.message}"
          end
        end

        MlFullStock.upsert_all(rows, unique_by: %i[ml_account_id inventory_id]) if rows.any?
        Result.new(notes: notes, count: rows.size)
      end

      def self.inventory_ids(account)
        account.ml_items.where(status: %w[active paused], logistic_type: "fulfillment")
          .pluck(:inventory_refs)
          .flat_map { |refs| refs.filter_map { |ref| ref["inventory_id"].presence } }
          .uniq
      end
      private_class_method :inventory_ids

      def self.row_for(account, inventory_id, body)
        available = body["available_units"].to_i
        not_available = body["not_available_units"].to_i
        {
          ml_account_id: account.id,
          inventory_id: inventory_id,
          available_units: available,
          not_available_units: not_available,
          total_units: body["total"] || (available + not_available),
          not_available_detail: body["not_available_detail"] || [],
          synced_at: Time.current
        }
      end
      private_class_method :row_for
    end
  end
end
