# Anúncios › filtros "Anúncios criados há mais de" e "Quantidade de Vendas" pelo ANÚNCIO PAI (pedido do usuário em
# 25/11/2026). No modelo de User Products do ML cada variação é um anúncio próprio e o pai é a família
# (`ml_items.family_id`, a mesma regra de Ml::ItemVariations: mesma família, mesmo tipo Clássico/Premium, fora do catálogo).
# Com algum dos dois filtros ligado, a tabela mostra só o pai (um anúncio por família) e o filtro olha a família inteira:
# - vendas = soma das vendas de todas as variações (3 + 4 = 7 entra em "5 a 9");
# - criação = a data do anúncio mais antigo da família (quando o pai foi criado).
# Assim nunca aparece "sem vendas" uma variação cujo pai ainda vende pelas outras. Anúncio de catálogo e anúncio sem
# família ficam sozinhos (família de um).
module Painel
  class ListingFamilies
    STATUS_RANK = { "active" => 0, "paused" => 1, "under_review" => 2 }.freeze

    Group = Struct.new(:key, :lead, :item_ids, :sold, :created, keyword_init: true) do
      def variations? = item_ids.size > 1
    end

    def self.for(account) = new(account)

    def initialize(account)
      @account = account
    end

    # todas as famílias da conta
    def groups
      @groups ||= @account.ml_items
                          .pluck(:item_id, :family_id, :listing_type_id, :catalog_listing, :sold_quantity, :date_created, :status)
                          .group_by { |id, family, type, catalog| catalog || family.blank? ? "item:#{id}" : "family:#{family}:#{type}" }
                          .map { |key, rows| build(key, rows) }
    end

    # famílias que passam nos filtros de criação e de vendas
    def matching(params)
      cutoff = Painel::CreatedFilter.cutoff(params)
      groups.select { |g| (cutoff.nil? || (g.created && g.created < cutoff)) && Painel::SalesFilter.match?(g.sold, params) }
    end

    # pai (anúncio que representa a família na tabela) de cada família que passa nos filtros
    def lead_ids(params) = matching(params).map(&:lead)

    def by_item = @by_item ||= groups.each_with_object({}) { |g, h| g.item_ids.each { |id| h[id] = g } }

    def group_of(item_id) = by_item[item_id.to_s]

    # anúncio + as outras variações da mesma família (para excluir o pai inteiro)
    def expand(item_ids)
      Array(item_ids).map(&:to_s).flat_map { |id| group_of(id)&.item_ids || [ id ] }.uniq
    end

    private

    # pai = a variação que melhor representa a família: ativa antes de pausada/finalizada, depois a que mais vendeu
    def build(key, rows)
      lead = rows.min_by { |id, _f, _t, _c, sold, _d, status| [ STATUS_RANK.fetch(status, 3), -sold.to_i, id ] }
      Group.new(key: key, lead: lead[0], item_ids: rows.map(&:first).sort, sold: rows.sum { |r| r[4].to_i },
                created: rows.filter_map { |r| r[5] }.min)
    end
  end
end
