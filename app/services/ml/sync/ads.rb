# Seção Ads: lê do Mercado Livre (somente leitura) as campanhas de Product Ads, as métricas de cada
# campanha por dia e os anúncios em campanha com as métricas de 7, 30 e 90 dias. A API limita a
# consulta a 90 dias.
module Ml
  module Sync
    module Ads
      WINDOWS = { "7d" => 7, "30d" => 30, "90d" => 90 }.freeze
      PAGE = 100
      MAX_PAGES = 30
      RECENT_ITEM_DAYS = 3        # dias relidos a cada leitura rápida (hoje, ontem e anteontem)
      BACKFILL_DAYS_PER_RUN = 8   # dias antigos ainda não lidos, por leitura
      MISMATCH_DAYS_PER_RUN = 2   # dias com soma por anúncio diferente da das campanhas, relidos por leitura

      Result = Struct.new(:campaigns, :items, :days, :notes, :ok, keyword_init: true)

      def self.call(client, account, today: Date.current)
        notes = []
        advertiser_id = advertiser(client, notes)
        return Result.new(campaigns: 0, items: 0, days: 0, notes: notes, ok: false) unless advertiser_id

        to = today
        from = today - (WINDOWS.fetch("90d") - 1)
        now = Time.current

        campaigns = campaigns(client, account, advertiser_id, from, to, now, notes)
        days = daily(client, account, advertiser_id, campaigns, from, to, notes)
        items = items(client, account, advertiser_id, today, now, notes)
        account.update_columns(ads_synced_at: now, ads_recent_synced_at: now, ads_advertiser_id: advertiser_id)
        item_days(client, account, today, advertiser_id)

        Result.new(campaigns: campaigns.size, items: items, days: days, notes: notes.first(5), ok: notes.empty?)
      end

      # Leitura rápida (a cada 30 min): só ontem e hoje de cada campanha já conhecida, para o "Hoje" da tela.
      def self.refresh_recent(client, account, today: Date.current)
        notes = []
        advertiser_id = account.ads_advertiser_id || advertiser(client, notes)
        return Result.new(campaigns: 0, items: 0, days: 0, notes: notes, ok: false) unless advertiser_id

        ids = account.ml_ad_campaigns.pluck(:campaign_id)
        days = daily(client, account, advertiser_id, ids, today - 1, today, notes)
        account.update_columns(ads_recent_synced_at: Time.current, ads_advertiser_id: advertiser_id)
        item_days(client, account, today, advertiser_id)
        Result.new(campaigns: ids.size, items: 0, days: days, notes: notes.first(5), ok: notes.empty?)
      end

      # Gasto por anúncio e por dia (para ratear o custo de Ads entre as vendas): relê os últimos dias, até
      # fecharem, e baixa aos poucos os dias antigos que faltam.
      def self.item_days(client, account, today, advertiser_id, backfill: BACKFILL_DAYS_PER_RUN)
        recent = ((today - (RECENT_ITEM_DAYS - 1))..today).to_a
        sync_item_days(client, account, recent, advertiser_id: advertiser_id)
        sync_item_days(client, account, mismatched_item_days(account, today, recent).first(MISMATCH_DAYS_PER_RUN), advertiser_id: advertiser_id)
        backfill_item_days(client, account, today: today, max: backfill, advertiser_id: advertiser_id)
      end

      # Dias lidos logo depois de fechar em que a soma por anúncio não bate com o gasto das campanhas (leitura
      # incompleta): são relidos uma vez. Se a diferença continua, é do próprio ML e Vendas a mostra como Ads sem venda.
      def self.mismatched_item_days(account, today, skip = [])
        from = today - (WINDOWS.fetch("90d") - 1)
        campaigns = account.ml_ad_daily_metrics.where(date: from..today).group(:date).sum(:cost)
        items = MlAdItemDaily.where(ml_account_id: account.id, date: from..today).group(:date).sum(:cost)
        early = account.ml_ad_day_syncs.where(date: from..today).select { |s| s.fetched_at.in_time_zone.to_date <= s.date + 1 }
          .map(&:date).to_set
        campaigns.filter_map { |date, cost| date if early.include?(date) && !skip.include?(date) && (cost.to_f - items[date].to_f).abs >= 0.01 }
          .sort.reverse
      end

      # Baixa os dias dos últimos 90 que ainda não foram lidos (os mais novos primeiro).
      def self.backfill_item_days(client, account, today: Date.current, max: nil, advertiser_id: nil)
        wanted = ((today - (WINDOWS.fetch("90d") - 1))..today).to_a.reverse
        missing = wanted - account.ml_ad_day_syncs.pluck(:date)
        missing = missing.first(max) if max
        sync_item_days(client, account, missing, advertiser_id: advertiser_id)
      end

      # Lê, dia a dia, o gasto de cada anúncio. Dia com erro não é marcado como lido (será tentado de novo).
      def self.sync_item_days(client, account, dates, advertiser_id: nil)
        advertiser_id ||= account.ads_advertiser_id || advertiser(client, [])
        return 0 unless advertiser_id

        done = 0
        dates.each do |date|
          notes = []
          rows = paginate(notes, "gasto do dia #{date}", PAGE) do |offset|
            client.ads_items(advertiser_id, from: date, to: date, offset: offset, limit: PAGE)
          end
          next if notes.any?

          save_item_day(account, date, rows)
          done += 1
        end
        done
      end

      def self.save_item_day(account, date, rows)
        now = Time.current
        records = rows.filter_map do |ad|
          m = ad["metrics"] || {}
          next unless m["cost"].to_f.positive? || m["clicks"].to_i.positive? || m["units_quantity"].to_i.positive?

          { ml_account_id: account.id, item_id: ad["item_id"], date: date, campaign_id: ad["campaign_id"], cost: m["cost"].to_f,
            clicks: m["clicks"].to_i, prints: m["prints"].to_i, total_amount: m["total_amount"].to_f, units: m["units_quantity"].to_i }
        end

        MlAdItemDaily.transaction do
          MlAdItemDaily.where(ml_account_id: account.id, date: date).delete_all
          MlAdItemDaily.insert_all(records) if records.any?
          MlAdDaySync.upsert({ ml_account_id: account.id, date: date, fetched_at: now }, unique_by: :index_ml_ad_day_syncs_unique)
        end
      end

      # Métricas por anúncio de um período qualquer (hoje, ontem, datas escolhidas), consultadas na hora.
      # => { item_id => métricas da API } ou nil se o Mercado Livre não respondeu.
      def self.live_items(client, account, from, to)
        notes = []
        advertiser_id = account.ads_advertiser_id || advertiser(client, notes)
        return nil unless advertiser_id

        rows = paginate(notes, "anúncios", PAGE) do |offset|
          client.ads_items(advertiser_id, from: from, to: to, offset: offset, limit: PAGE)
        end
        return nil if rows.empty? && notes.any?

        rows.to_h { |ad| [ ad["item_id"], ad["metrics"] || {} ] }
      end

      def self.advertiser(client, notes)
        response = client.ads_advertisers
        Array(response["advertisers"]).find { |a| a["site_id"] == "MLB" }&.dig("advertiser_id") ||
          (notes << "Sem conta de publicidade (Product Ads) no Mercado Livre." and nil)
      rescue Ml::Client::Error => e
        notes << "publicidade: #{e.message}"
        nil
      end
      private_class_method :advertiser

      def self.campaigns(client, account, advertiser_id, from, to, now, notes)
        rows = paginate(notes, "campanhas", 50) { |offset| client.ads_campaigns(advertiser_id, from: from, to: to, offset: offset, limit: 50) }
        return [] if rows.empty?

        records = rows.map do |c|
          {
            ml_account_id: account.id, campaign_id: c["id"], name: c["name"], status: c["status"], strategy: c["strategy"],
            channel: c["channel"], acos_target: c["acos_target"], roas_target: c["roas_target"], budget: c["budget"],
            daily_budget: c["daily_budget"], automatic_budget: c["automatic_budget"], date_created: c["date_created"],
            last_updated: c["last_updated"], synced_at: now, created_at: now, updated_at: now
          }
        end
        MlAdCampaign.upsert_all(records, unique_by: [ :ml_account_id, :campaign_id ])
        rows.map { |c| c["id"] }
      end
      private_class_method :campaigns

      def self.daily(client, account, advertiser_id, campaign_ids, from, to, notes)
        total = 0
        campaign_ids.each do |campaign_id|
          rows = paginate(notes, "dias da campanha #{campaign_id}", PAGE) do |offset|
            client.ads_items(advertiser_id, from: from, to: to, offset: offset, limit: PAGE, campaign_id: campaign_id, daily: true)
          end
          records = rows.filter_map { |r| daily_record(account, campaign_id, r) }
          next if records.empty?

          MlAdDailyMetric.upsert_all(records, unique_by: :index_ml_ad_daily_unique)
          total += records.size
        end
        total
      end
      private_class_method :daily

      def self.daily_record(account, campaign_id, row)
        return nil if row["date"].blank?

        {
          ml_account_id: account.id, campaign_id: campaign_id, date: row["date"], clicks: row["clicks"].to_i, prints: row["prints"].to_i,
          cost: row["cost"].to_f, direct_amount: row["direct_amount"].to_f, indirect_amount: row["indirect_amount"].to_f,
          total_amount: row["total_amount"].to_f, direct_units: row["direct_units_quantity"].to_i,
          indirect_units: row["indirect_units_quantity"].to_i, units: row["units_quantity"].to_i,
          organic_units: row["organic_units_quantity"].to_i, organic_amount: row["organic_units_amount"].to_f
        }
      end
      private_class_method :daily_record

      # Um anúncio por linha, com as métricas de cada janela (7, 30 e 90 dias).
      def self.items(client, account, advertiser_id, today, now, notes)
        by_item = {}
        WINDOWS.each do |key, days|
          rows = paginate(notes, "anúncios #{key}", PAGE) do |offset|
            client.ads_items(advertiser_id, from: today - (days - 1), to: today, offset: offset, limit: PAGE)
          end
          rows.each do |ad|
            entry = by_item[ad["item_id"]] ||= { base: ad, metrics: {} }
            entry[:base] = ad if key == "90d"
            entry[:metrics][key] = ad["metrics"] || {}
          end
        end
        return 0 if by_item.empty?

        records = by_item.map { |item_id, entry| item_record(account, item_id, entry, now) }
        MlAdItem.upsert_all(records, unique_by: [ :ml_account_id, :item_id ])
        MlAdItem.where(ml_account_id: account.id).where("synced_at < ?", now).delete_all
        records.size
      end
      private_class_method :items

      def self.item_record(account, item_id, entry, now)
        ad = entry[:base]
        {
          ml_account_id: account.id, item_id: item_id, campaign_id: ad["campaign_id"], ad_group_id: ad["ad_group_id"],
          title: ad["title"], status: ad["status"], price: ad["price"], thumbnail: ad["thumbnail"], permalink: ad["permalink"],
          listing_type_id: ad["listing_type_id"], logistic_type: ad["logistic_type"], catalog_listing: ad["catalog_listing"],
          buy_box_winner: ad["buy_box_winner"], recommended: ad["recommended"], has_discount: ad["has_discount"],
          condition: ad["condition"], date_created: ad["date_created"], metrics: entry[:metrics], synced_at: now,
          created_at: now, updated_at: now
        }
      end
      private_class_method :item_record

      # Lê todas as páginas de uma consulta paginada por offset.
      def self.paginate(notes, label, step)
        rows = []
        MAX_PAGES.times do |page|
          response = yield(page * step)
          results = response["results"] || []
          rows.concat(results)
          total = response.dig("paging", "total").to_i
          break if results.empty? || rows.size >= total
        end
        rows
      rescue Ml::Client::Error => e
        notes << "#{label}: #{e.message}"
        rows || []
      end
      private_class_method :paginate
    end
  end
end
