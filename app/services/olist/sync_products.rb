# Sincroniza os produtos (cadastro, preços, custo e estoque) do Olist ERP para
# o banco do Lunna. Lê todas as páginas de /produtos e de /estoque; só depois de
# ler TUDO é que grava (upsert) e remove o que sumiu do Olist — uma falha no meio
# nunca deixa a cópia local pela metade.
module Olist
  class SyncProducts
    # Cria (ou reaproveita, se já houver uma rodada em andamento) o registro da
    # rodada. Devolve [run, created].
    def self.start_run(connection, trigger:, user: nil)
      company_id = connection.company_id

      connection.with_lock do
        mark_stale_runs_failed(company_id)
        active = OlistSyncRun.active.find_by(company_id: company_id)
        next [ active, false ] if active

        run = OlistSyncRun.create!(
          company_id: company_id, trigger: trigger, requested_by_user: user, status: "running", started_at: Time.current
        )
        [ run, true ]
      end
    end

    def self.mark_stale_runs_failed(company_id)
      OlistSyncRun.where(company_id: company_id, status: "running")
        .where(started_at: ...OlistSyncRun::STALE_AFTER.ago)
        .update_all(status: "failed", error: OlistSyncRun::STALE_ERROR, finished_at: Time.current)
    end

    def initialize(connection, run, client: Olist::Client.new(connection))
      @connection = connection
      @run = run
      @client = client
    end

    def call
      products = @client.all(:products)
      stock = @client.all(:stock).index_by { |item| item["idProduto"] }
      now = Time.current
      rows = products.map { |item| row_for(item, stock[item["id"]], now) }

      OlistProduct.transaction do
        OlistProduct.upsert_all(rows, unique_by: %i[company_id olist_id]) if rows.any?
        OlistProduct.where(company_id: @connection.company_id).where(synced_at: ...now).delete_all
      end

      link_variations

      @run.update!(status: "success", products_count: rows.size, finished_at: Time.current, error: nil)
    rescue Olist::Client::Error, Olist::OAuth::Error => e
      Rails.logger.error("Olist::SyncProducts: #{e.class}")
      @run.update!(status: "failed", error: user_message(e), finished_at: Time.current)
    rescue StandardError => e
      Rails.logger.error("Olist::SyncProducts: erro inesperado (#{e.class})")
      @run.update!(status: "failed", error: "Erro inesperado na sincronização.", finished_at: Time.current)
    end

    private

    # Liga cada variação ao seu produto pai. A listagem do Olist não diz quem é o pai;
    # quem sabe é o próprio pai (GET /produtos/{id} traz `variacoes`). Só relê o pai
    # quando ele mudou desde a última leitura (ou ainda não foi lido), e, se sobrar
    # variação sem pai, relê os demais. Falha ao ler um pai mantém o vínculo anterior.
    def link_variations
      company_id = @connection.company_id
      parents = OlistProduct.where(company_id: company_id, variation_kind: "P").to_a
      refreshed = refresh_parents(parents.select { |parent| variations_stale?(parent) })
      assign_parents(company_id)

      # Variação excluída sem pai é normal (o pai foi apagado); só as ativas/inativas sem pai justificam reler os outros.
      return unless OlistProduct.where(company_id: company_id, variation_kind: "V", parent_olist_id: nil).where.not(status: "E").exists?

      refresh_parents(parents - refreshed)
      assign_parents(company_id)
    end

    def variations_stale?(parent)
      parent.variations_source_updated_at != source_marker(parent)
    end

    def source_marker(parent)
      parent.olist_updated_at || Time.zone.at(0)
    end

    def refresh_parents(parents)
      parents.each do |parent|
        detail = @client.product(parent.olist_id)
        ids = (detail["variacoes"] || []).filter_map { |variation| variation["id"] }
        parent.update!(variation_ids: ids, variations_source_updated_at: source_marker(parent))
      rescue Olist::Client::Error, Olist::OAuth::Error => e
        Rails.logger.warn("Olist::SyncProducts: não foi possível ler as variações do produto #{parent.olist_id} (#{e.class})")
      end
      parents
    end

    def assign_parents(company_id)
      by_parent = OlistProduct.where(company_id: company_id, variation_kind: "P").to_h { |parent| [ parent.olist_id, parent.variation_ids.map(&:to_i) ] }
      linked = by_parent.values.flatten

      by_parent.each do |parent_id, child_ids|
        OlistProduct.where(company_id: company_id, olist_id: child_ids).update_all(parent_olist_id: parent_id)
      end
      OlistProduct.where(company_id: company_id).where.not(olist_id: linked).where.not(parent_olist_id: nil).update_all(parent_olist_id: nil)
    end

    def row_for(item, stock, now)
      prices = item["precos"] || {}
      {
        company_id: @connection.company_id,
        olist_id: item["id"],
        sku: item["sku"],
        description: item["descricao"],
        kind: item["tipo"],
        status: item["situacao"],
        variation_kind: item["tipoVariacao"],
        unit: item["unidade"],
        gtin: item["gtin"],
        price: prices["preco"],
        promo_price: prices["precoPromocional"],
        cost_price: prices["precoCusto"],
        avg_cost_price: prices["precoCustoMedio"],
        stock_balance: stock&.dig("saldo"),
        stock_reserved: stock&.dig("reservado"),
        stock_available: stock&.dig("disponivel"),
        stock_location: stock&.dig("localizacao") || item.dig("estoque", "localizacao"),
        stock_deposits: stock&.dig("depositos") || [],
        olist_created_at: parse_time(item["dataCriacao"]),
        olist_updated_at: parse_time(item["dataAlteracao"]),
        synced_at: now
      }
    end

    # O Olist devolve "aaaa-mm-dd hh:mm:ss" no horário de Brasília.
    def parse_time(value)
      return nil if value.blank?

      ActiveSupport::TimeZone["America/Sao_Paulo"].parse(value)
    end

    def user_message(error)
      return "O Olist pede para conectar de novo." if error.is_a?(Olist::OAuth::Error) || (error.respond_to?(:status) && error.status == 401)

      "Não foi possível consultar o Olist agora."
    end
  end
end
