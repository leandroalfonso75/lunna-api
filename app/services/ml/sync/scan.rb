# Etapa 1 (SPEC 4): lista todos os IDs de anúncio (qualquer status) via scan,
# 100 por página, até 100 páginas; para na primeira página vazia.
module Ml
  module Sync
    module Scan
      MAX_PAGES = 100

      Result = Struct.new(:ids, :notes, keyword_init: true)

      def self.call(client, seller_id)
        ids = []
        notes = []
        scroll_id = nil

        MAX_PAGES.times do
          begin
            page = client.items_scan(seller_id, scroll_id: scroll_id)
          rescue Ml::Client::Error => e
            notes << "scan: #{e.message}"
            break
          end

          results = page["results"] || []
          break if results.empty?

          ids.concat(results)
          scroll_id = page["scroll_id"]
        end

        Result.new(ids: ids, notes: notes)
      end
    end
  end
end
