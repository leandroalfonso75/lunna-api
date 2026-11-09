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
        }.merge(clip_attrs(data))
      end
      private_class_method :attrs_from

      # Vídeo no formato atual do ML (clip/shorts) não vem em video_id: a regra HAS_SHORTS (ou UP_HAS_SHORTS) da
      # qualidade diz se o anúncio tem vídeo (COMPLETED) ou não (PENDING). Corrigido em 09/11/2026 (MLB2729901870
      # tinha vídeo e o Lunna sugeria incluir).
      SHORTS_KEYS = %w[HAS_SHORTS UP_HAS_SHORTS SHORTS HAS_VIDEO VIDEO].freeze

      def self.clip_attrs(data)
        rules = (data["buckets"] || []).flat_map { |b| (b["variables"] || []).flat_map { |v| [ v ] + (v["rules"] || []) } }
        found = rules.select { |r| SHORTS_KEYS.include?(r["key"].to_s) }
        return {} if found.empty?

        { has_clip: found.any? { |r| r["status"] == "COMPLETED" } }
      end

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
