# Anúncios › "Excluir anúncios selecionados" (pedido do usuário em 24/11/2026). No Mercado Livre excluir é em dois passos:
# finalizar o anúncio (PUT /items/{id} status=closed) e depois marcar como excluído (PUT /items/{id} deleted=true).
# Não tem volta: anúncio excluído some do painel do ML e não pode ser reativado (só republicado como anúncio novo).
# Escrita no ML: só admin, com confirmação na tela, cada anúncio registrado em ml_item_edits (kind "exclusao").
# Um anúncio que o ML recusar não impede os outros; o resultado vem por anúncio.
module Ml
  class ItemDeletion
    MAX_ITEMS = 50
    Result = Struct.new(:item_id, :ok, :message, keyword_init: true)

    def self.call(client, account, item_ids, user:) = new(client, account, user).call(item_ids)

    def initialize(client, account, user)
      @client = client
      @account = account
      @user = user
    end

    def call(item_ids)
      ids = Array(item_ids).map(&:to_s).reject(&:blank?).uniq
      own = @account.ml_items.where(item_id: ids).index_by(&:item_id)
      ids.map { |id| own[id] ? delete(own[id]) : Result.new(item_id: id, ok: false, message: "Anúncio não encontrado nesta conta.") }
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
