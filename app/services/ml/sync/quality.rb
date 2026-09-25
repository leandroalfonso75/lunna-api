# Etapa 5 (SPEC 4): nota de qualidade dos anúncios active vencidos (o Run
# seleciona o lote a partir de quality_checked_at). 5 threads;
# `update_all` por item (não upsert — só algumas colunas mudam,
# DECISOES §6). O carimbo quality_checked_at é gravado mesmo com erro, pra
# não repetir o mesmo anúncio em loop.
module Ml
  module Sync
    module Quality
      THREADS = 5

      Result = Struct.new(:notes, keyword_init: true)

      def self.call(client, item_ids)
        notes = []
        results = Ml::Sync::Parallel.map(item_ids, threads: THREADS) { |item_id| client.item_performance(item_id) }

        results.each_with_index do |(status, value), i|
          item_id = item_ids[i]

          if status == :ok
            MlItem.where(item_id: item_id).update_all(attrs_from(value))
          else
            notes << "qualidade #{item_id}: #{value.message}"
            MlItem.where(item_id: item_id).update_all(quality_checked_at: Time.current)
          end
        end

        Result.new(notes: notes)
      end

      def self.attrs_from(data)
        {
          quality_score: data["score"],
          quality_level: data["level_wording"].presence || data["level"],
          quality_pending: pending_rules(data),
          quality_checked_at: Time.current
        }
      end
      private_class_method :attrs_from

      # Uma entrada por regra com status PENDING em buckets[].variables[].rules[].
      def self.pending_rules(data)
        (data["buckets"] || []).flat_map do |bucket|
          (bucket["variables"] || []).flat_map do |variable|
            (variable["rules"] || [])
              .select { |rule| rule["status"] == "PENDING" }
              .map do |rule|
                {
                  area: bucket["title"],
                  key: rule["key"],
                  title: rule.dig("wordings", "title"),
                  label: rule.dig("wordings", "label"),
                  mode: rule["mode"]
                }
              end
          end
        end
      end
      private_class_method :pending_rules
    end
  end
end
