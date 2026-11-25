# Anúncios › "Excluir anúncios selecionados" (pedido do usuário em 24/11/2026). No Mercado Livre excluir é em dois passos:
# finalizar o anúncio (PUT /items/{id} status=closed) e depois marcar como excluído (PUT /items/{id} deleted=true).
# Não tem volta: anúncio excluído some do painel do ML e não pode ser reativado (só republicado como anúncio novo).
# Escrita no ML: só admin, com confirmação na tela, cada anúncio registrado em ml_item_edits (kind "exclusao").
# Um anúncio que o ML recusar não impede os outros; o resultado vem por anúncio.
#
# Tradicional sincronizado com catálogo (25/11/2026): a tela avisa que o anúncio de catálogo também será excluído e, com
# a confirmação (with_catalog), o catálogo é excluído primeiro e depois o tradicional. Se o catálogo não puder ser
# excluído, o tradicional fica como está (não deixa catálogo órfão).
module Ml
  class ItemDeletion
    MAX_ITEMS = 50
    # anúncio pai com variações (25/11/2026): a seleção (até 50) pode virar mais anúncios ao incluir as variações
    MAX_EXPANDED = 200
    Result = Struct.new(:item_id, :ok, :message, :catalog_of, keyword_init: true)

    def self.call(client, account, item_ids, user:, with_catalog: false) = new(client, account, user).call(item_ids, with_catalog: with_catalog)

    # { tradicional selecionado => [anúncios de catálogo sincronizados a ele, ainda não finalizados] }
    # Vale também quando o catálogo já está na seleção: ele sai junto com o tradicional, antes dele.
    def self.linked_catalogs(account, item_ids)
      ids = Array(item_ids).map(&:to_s).uniq
      traditional = account.ml_items.where(item_id: ids, catalog_listing: [ false, nil ]).pluck(:item_id)
      sync = Painel::CatalogSync.for(account)
      linked = traditional.to_h { |id| [ id, sync.catalog_ids_for(id) ] }.reject { |_, cats| cats.empty? }
      open = account.ml_items.where(item_id: linked.values.flatten, catalog_listing: true).where.not(status: "closed").pluck(:item_id).to_set
      linked.transform_values { |cats| cats.select { |c| open.include?(c) } }.reject { |_, cats| cats.empty? }
    end

    def initialize(client, account, user)
      @client = client
      @account = account
      @user = user
    end

    def call(item_ids, with_catalog: false)
      ids = Array(item_ids).map(&:to_s).reject(&:blank?).uniq
      linked = with_catalog ? self.class.linked_catalogs(@account, ids) : {}
      own = @account.ml_items.where(item_id: ids + linked.values.flatten).index_by(&:item_id)
      done = {}
      ids.each do |id|
        next if done.key?(id) # catálogo selecionado que já saiu junto com o seu tradicional
        unless own[id]
          done[id] = Result.new(item_id: id, ok: false, message: "Anúncio não encontrado nesta conta.")
          next
        end
        catalogs = Array(linked[id]).reject { |cid| done.key?(cid) }.filter_map { |cid| own[cid] }
                                    .map { |cat| done[cat.item_id] = delete(cat).tap { |r| r.catalog_of = id } }
        done[id] = if catalogs.any? { |r| !r.ok }
          Result.new(item_id: id, ok: false, message: "Não excluído: o anúncio de catálogo sincronizado não pôde ser excluído.")
        else
          delete(own[id])
        end
      end
      done.values
    end

    private

    def delete(item)
      edit = @account.ml_item_edits.create!(item_id: item.item_id, user: @user, kind: "exclusao",
                                            before: { status: item.status, title: item.title, sku: item.sku }, after: { deleted: true })
      @client.update_item(item.item_id, { status: "closed" }) unless item.status == "closed"
      @client.update_item(item.item_id, { deleted: "true" })
      edit.update!(ok: true)
      item.update_columns(status: "closed")
      @account.item_metrics.where(item_id: item.item_id).update_all(status: "closed")
      Result.new(item_id: item.item_id, ok: true, message: "Excluído do Mercado Livre.")
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(2000))
      # já finalizado no primeiro passo: o status local acompanha, mesmo que a marcação de excluído falhe
      if (fresh = (@client.item_info(item.item_id) rescue nil)) && fresh["status"] == "closed"
        item.update_columns(status: "closed")
        @account.item_metrics.where(item_id: item.item_id).update_all(status: "closed")
      end
      Result.new(item_id: item.item_id, ok: false, message: "O Mercado Livre recusou: #{Ml::ItemSpecs.ml_reason(e.message)}")
    end
  end
end
