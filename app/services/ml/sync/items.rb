# Etapa 2 (SPEC 4): multiget de 20 em 20 e upsert_all de 200 em 200 em
# ml_items. Item com code != 200 (ex.: 404 por ter sido apagado entre o scan
# e o multiget) vira nota; os demais seguem.
module Ml
  module Sync
    module Items
      BATCH_SIZE = 20
      UPSERT_BATCH_SIZE = 200

      Result = Struct.new(:ids, :notes, keyword_init: true)

      def self.call(client, account, item_ids)
        rows = []
        notes = []

        item_ids.each_slice(BATCH_SIZE) do |batch|
          begin
            entries = client.items_multiget(batch)
          rescue Ml::Client::Error => e
            notes << "multiget #{batch.join(",")}: #{e.message}"
            next
          end

          entries.each_with_index do |entry, i|
            if entry["code"] == 200
              rows << Ml::ItemAttributes.from(entry["body"], account)
            else
              notes << "item #{batch[i]}: HTTP #{entry["code"]} no multiget"
            end
          end
        end

        rows.each_slice(UPSERT_BATCH_SIZE) do |batch|
          MlItem.upsert_all(batch, unique_by: :item_id)
        end

        Result.new(ids: rows.map { |row| row[:item_id] }, notes: notes)
      end
    end
  end
end
