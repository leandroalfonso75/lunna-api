# Anúncios > aba Catálogo (pedido do usuário em 08/11/2026): todos os anúncios de catálogo, se estão sincronizados com
# um anúncio tradicional (item_relations, como em Promoções) e se estão ganhando ou perdendo a vitrine do catálogo
# (price_to_win, lido a cada 30 minutos para os ativos).
module Painel
  class CatalogQuery
    STATES = Painel::PromotionsQuery::CATALOG_STATES
    STATE_LABELS = { "ganhando" => "Ganhando", "compartilhando" => "Compartilhando o 1º lugar", "perdendo" => "Perdendo",
                     "sem_dados" => "Sem leitura" }.freeze
    REASONS = {
      "winning" => nil, "manufacturing_time" => "prazo de fabricação", "shipping_full" => "concorrente no Full",
      "free_shipping" => "concorrente com frete grátis", "price" => "preço", "reputation" => "reputação",
      "same_day_shipping" => "concorrente com envio no mesmo dia", "non_trusted_seller" => "vendedor não confiável",
      "item_condition" => "condição do produto", "shipping" => "envio", "installments" => "parcelamento"
    }.freeze
    STATUS_LABELS = { "active" => "Ativo", "paused" => "Pausado", "closed" => "Encerrado", "under_review" => "Em revisão",
                      "inactive" => "Inativo" }.freeze

    def self.call(account, params) = new(account, params).call

    def initialize(account, params)
      @account = account
      @params = params
    end

    def call
      items = @account.ml_items.where(catalog_listing: true).to_a
      related_ids = items.flat_map { |i| Array(i.item_relations).map { |r| r["id"] } }.compact.uniq
      related = @account.ml_items.where(item_id: related_ids).index_by(&:item_id)
      metrics = @account.item_metrics.where(item_id: items.map(&:item_id)).index_by(&:item_id)
      skus = ItemSkus.for(@account, items.map(&:item_id))
      rows = items.map { |i| row(i, related, metrics[i.item_id], skus[i.item_id] || []) }

      all = rows
      rows = rows.select { |r| r[:sync] == @params[:sync] } if %w[sincronizado nao_sincronizado].include?(@params[:sync].to_s)
      rows = rows.select { |r| r[:state] == @params[:state] } if STATE_LABELS.key?(@params[:state].to_s)
      rows = rows.select { |r| r[:status] == @params[:status] } if @params[:status].present?
      if (q = @params[:q].to_s.strip.downcase).present?
        rows = rows.select { |r| [ r[:item_id], r[:title], *r[:skus], *r[:related].map { |x| x[:item_id] } ].compact.any? { |v| v.to_s.downcase.include?(q) } }
      end
      order = { "ganhando" => 1, "compartilhando" => 1, "perdendo" => 0, "sem_dados" => 2 }
      rows = rows.sort_by { |r| [ r[:status] == "active" ? 0 : 1, order[r[:state]], -r[:units_30d].to_i ] }

      {
        counts: {
          total: all.size, sincronizado: all.count { |r| r[:sync] == "sincronizado" }, nao_sincronizado: all.count { |r| r[:sync] == "nao_sincronizado" },
          ganhando: all.count { |r| %w[ganhando compartilhando].include?(r[:state]) }, perdendo: all.count { |r| r[:state] == "perdendo" },
          sem_dados: all.count { |r| r[:state] == "sem_dados" }, ativos: all.count { |r| r[:status] == "active" }
        },
        checked_at: items.filter_map(&:catalog_checked_at).max,
        items: rows
      }
    end

    private

    def row(i, related, metric, skus)
      state = STATES[i.catalog_status] || "sem_dados"
      rel = Array(i.item_relations).filter_map do |r|
        t = related[r["id"]]
        { item_id: r["id"], title: t&.title, status: t&.status, status_label: t && (STATUS_LABELS[t.status] || t.status), price: t&.price&.to_f }
      end
      reasons = Array(i.catalog_reasons).filter_map { |x| REASONS.fetch(x.to_s, x.to_s.tr("_", " ")) }
      {
        item_id: i.item_id, title: i.title, thumbnail: i.thumbnail, permalink: i.permalink, catalog_product_id: i.catalog_product_id,
        status: i.status, status_label: STATUS_LABELS[i.status] || i.status, price: i.price&.to_f, stock: i.available_quantity,
        skus: skus, units_30d: metric&.units_30d.to_i,
        sync: rel.any? ? "sincronizado" : "nao_sincronizado", related: rel,
        state: state, state_label: STATE_LABELS[state], ml_status: i.catalog_status, reasons: reasons,
        price_to_win: i.catalog_price_to_win&.to_f, winner_price: i.catalog_winner_price&.to_f, checked_at: i.catalog_checked_at
      }
    end
  end
end
