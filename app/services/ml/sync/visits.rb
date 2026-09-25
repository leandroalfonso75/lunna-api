# Etapa 3 (SPEC 4): visitas dos últimos 60 dias dos anúncios active/paused
# (o Run decide quando rodar, a partir de visits_synced_at). 5 threads;
# upsert de 500 em 500 em ml_item_visits. Dia = 10 primeiros caracteres da
# data devolvida pelo ML, sem converter fuso (SPEC/DECISOES §1).
module Ml
  module Sync
    module Visits
      THREADS = 5
      UPSERT_BATCH_SIZE = 500

      Result = Struct.new(:notes, keyword_init: true)

      def self.call(client, account, item_ids)
        notes = []
        rows = []

        results = Ml::Sync::Parallel.map(item_ids, threads: THREADS) { |item_id| client.item_visits(item_id) }

        results.each_with_index do |(status, value), i|
          item_id = item_ids[i]

          if status == :ok
            (value["results"] || []).each do |entry|
              rows << { item_id: item_id, ml_account_id: account.id, day: entry["date"].to_s[0, 10], visits: entry["total"] }
            end
          else
            notes << "visitas #{item_id}: #{value.message}"
          end
        end

        rows.each_slice(UPSERT_BATCH_SIZE) { |batch| MlItemVisit.upsert_all(batch) }

        Result.new(notes: notes)
      end
    end
  end
end
