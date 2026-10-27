# Orquestra uma rodada de sincronização (SPEC 4, DECISOES §6): resolve qual
# rodada usar (ou se já tem uma em andamento), roda as etapas em ordem e
# fecha o registro em ml_sync_runs. Só a falha da etapa 0 (renovar token)
# encerra a rodada com ok: false; as demais falhas viram nota e a rodada
# segue com ok: true.
module Ml
  module Sync
    class Run
      STALE_AFTER = 6.minutes
      VISITS_EVERY = 30.minutes
      QUALITY_EVERY = 6.hours
      DETAILS_EVERY = 12.hours
      QUALITY_BATCH = 200
      DETAILS_BATCH = 60
      SHIPMENTS_BATCH = 60
      CLAIMS_BATCH = 40
      ADS_EVERY = 3.hours
      ADS_RECENT_EVERY = 30.minutes
      DETAIL_MAX_LENGTH = 2_000

      # `sleeper:` só existe pra não dormir de verdade nos specs quando uma
      # etapa bate num 429/5xx (retentativa do Ml::Client) — em produção usa
      # o `sleep` real, igual ao default do próprio Client.
      def self.call(account, run_id: nil, sleeper: ->(seconds) { sleep(seconds) })
        new(account, run_id, sleeper).call
      end

      def initialize(account, run_id, sleeper)
        @account = account
        @run_id = run_id
        @sleeper = sleeper
        @notes = []
      end

      def call
        run = resolve_run!
        return unless run

        begin
          Ml::OAuth.refresh!(@account)
        rescue Ml::OAuth::Error
          run.update!(finished_at: Time.current, ok: false, detail: truncate(@account.last_error))
          return
        end

        client = Ml::Client.new(access_token: @account.access_token, sleeper: @sleeper)

        scan_result = Ml::Sync::Scan.call(client, @account.seller_id)
        @notes.concat(scan_result.notes)

        items_result = Ml::Sync::Items.call(client, @account, scan_result.ids)
        @notes.concat(items_result.notes)

        sync_full_stock(client)
        sync_visits(client)
        orders_result = sync_orders(client)
        sync_shipments(client)
        sync_claims(client)
        sync_ads(client)
        sync_quality(client)
        sync_details(client)

        Painel::ItemMetrics.refresh(@account)

        run.update!(
          finished_at: Time.current,
          ok: true,
          items: items_result.ids.size,
          orders: orders_result.order_ids.size,
          detail: truncate(@notes.join("\n"))
        )
      rescue StandardError => e
        # Erro inesperado (não é falha de API tratada como nota): fecha a rodada
        # como falha na hora, em vez de deixá-la aberta até virar "interrompida".
        run&.update_columns(finished_at: Time.current, ok: false,
          detail: truncate((@notes + [ "Erro inesperado na sincronização (#{e.class})." ]).join("\n")))
        raise
      end

      private

      # Fecha rodadas presas (>= 6 min sem terminar) antes de decidir se essa
      # execução pode seguir. Se ainda sobrar uma rodada em andamento que não
      # seja a que essa execução recebeu, não faz nada ("rodada anterior
      # ainda em andamento").
      def resolve_run!
        MlSyncRun.unfinished.where(ml_account: @account).where("started_at <= ?", STALE_AFTER.ago)
          .update_all(finished_at: Time.current, ok: false, detail: "interrompida")

        blocking = MlSyncRun.unfinished.where(ml_account: @account)
        blocking = blocking.where.not(id: @run_id) if @run_id
        return nil if blocking.exists?

        @run_id ? MlSyncRun.find(@run_id) : MlSyncRun.create!(ml_account: @account, started_at: Time.current)
      end

      # Estoque do Full direto do ML, a cada rodada (5 min).
      def sync_full_stock(client)
        result = Ml::Sync::FullStock.call(client, @account)
        @notes.concat(result.notes)
      end

      def sync_visits(client)
        return if @account.visits_synced_at.present? && @account.visits_synced_at > VISITS_EVERY.ago

        ids = @account.ml_items.where(status: %w[active paused]).pluck(:item_id)
        result = Ml::Sync::Visits.call(client, @account, ids)
        @notes.concat(result.notes)
        @account.update_columns(visits_synced_at: Time.current)
      end

      def sync_orders(client)
        backfilling = @account.orders_backfilled_at.nil?
        from = backfilling ? 95.days.ago.beginning_of_day : 4.days.ago.beginning_of_day

        result = Ml::Sync::Orders.call(client, @account, from: from)
        @notes.concat(result.notes)
        unless backfilling
          # vendas antigas alteradas (cancelamento, reclamação, devolução) também são relidas
          updated = Ml::Sync::Orders.call(client, @account, from: 2.days.ago, field: :updated)
          @notes.concat(updated.notes)
        end
        @account.update_columns(orders_backfilled_at: Time.current) if backfilling && result.ok

        result
      end

      # Publicidade (seção Ads): leitura completa a cada 3 horas e, entre elas, ontem e hoje a cada 30 minutos.
      def sync_ads(client)
        full_due = @account.ads_synced_at.nil? || @account.ads_synced_at <= ADS_EVERY.ago
        recent_due = @account.ads_recent_synced_at.nil? || @account.ads_recent_synced_at <= ADS_RECENT_EVERY.ago
        return unless full_due || recent_due

        result = full_due ? Ml::Sync::Ads.call(client, @account) : Ml::Sync::Ads.refresh_recent(client, @account)
        @notes.concat(result.notes)
      end

      # Envio dos pedidos recentes (seção Vendas), 60 por rodada.
      def sync_shipments(client)
        result = Ml::Sync::Shipments.call(client, @account, limit: SHIPMENTS_BATCH, since: 95.days.ago)
        @notes.concat(result.notes)
      end

      # Reclamações, cancelamentos por mediação e devoluções das vendas (motivo, resultado, devolução).
      def sync_claims(client)
        result = Ml::Sync::Claims.call(client, @account, limit: CLAIMS_BATCH, since: 95.days.ago)
        @notes.concat(result.notes)
      end

      # Anúncios de catálogo ficam de fora: /item/{id}/performance responde 400
      # "Product items are not supported" para todos eles (sem nota = "não calculou").
      def sync_quality(client)
        ids = @account.ml_items.where(status: "active", catalog_listing: [ false, nil ])
          .where("quality_checked_at IS NULL OR quality_checked_at <= ?", QUALITY_EVERY.ago)
          .order(Arel.sql("quality_checked_at ASC NULLS FIRST"))
          .limit(QUALITY_BATCH)
          .pluck(:item_id)

        result = Ml::Sync::Quality.call(client, ids)
        @notes.concat(result.notes)
      end

      def sync_details(client)
        items = @account.ml_items.where(status: %w[active paused under_review])
          .where("details_checked_at IS NULL OR details_checked_at <= ?", DETAILS_EVERY.ago)
          .order(Arel.sql("details_checked_at ASC NULLS FIRST"))
          .limit(DETAILS_BATCH)

        result = Ml::Sync::Details.call(client, @account, items)
        @notes.concat(result.notes)
      end

      def truncate(text)
        text.to_s[0, DETAIL_MAX_LENGTH]
      end
    end
  end
end
