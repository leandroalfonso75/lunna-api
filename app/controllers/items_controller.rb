# GET  /api/items (SPEC 10.4) → tabela de anúncios com filtros, busca, ordenação e paginação (Painel::ItemQuery); traz a
#      curva ABC e a data de criação de cada anúncio e ordena por elas (sort=curve|date_created, 24/11/2026)
#      ?created_older_than=N (dias) → só anúncios criados há mais de N dias (também em /api/items/catalog)
# GET  /api/items/bulk_edit?item_ids[]=   → confere se os selecionados podem ser editados juntos (um só ou mesmos SKUs)
# GET  /api/items/delete_preview?item_ids[]= → tradicionais selecionados sincronizados com catálogo e os catálogos que
#      sairão junto (a tela avisa antes de confirmar, 25/11/2026)
# POST /api/items/bulk_delete?account_id= → exclui do Mercado Livre (admin; item_ids[], confirm: true); resultado por anúncio.
#      Tradicional sincronizado com catálogo só sai com with_catalog: true, e o catálogo sai junto (antes dele).
#      with_variations: true (anúncio pai, 25/11/2026) → cada selecionado leva junto as outras variações da família.
class ItemsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :bulk_delete ]

  def index
    render json: Painel::ItemQuery.call(Current.account, params)
  end

  # GET /api/items/catalog → aba Catálogo: anúncios de catálogo, sincronização com tradicional e ganhando/perdendo
  def catalog
    render json: Painel::CatalogQuery.call(Current.account, params)
  end

  def bulk_edit
    result = Painel::BulkEditGroup.call(Current.account, params[:item_ids])
    render json: result.as_json, status: result.ok ? :ok : :unprocessable_content
  end

  def delete_preview
    ids = expand_variations(Array(params[:item_ids]).map(&:to_s).reject(&:blank?).uniq)
    linked = Ml::ItemDeletion.linked_catalogs(Current.account, ids)
    render json: { item_ids: ids, variations: variations_of(params[:item_ids]),
                   linked: linked.map { |id, cats| { item_id: id, catalogs: cats } } }
  end

  def bulk_delete
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para excluir no Mercado Livre." ], status: :unprocessable_content)
    end

    ids = Array(params[:item_ids]).map(&:to_s).reject(&:blank?).uniq
    return render_errors([ "Selecione ao menos um anúncio." ], status: :unprocessable_content) if ids.empty?
    if ids.size > Ml::ItemDeletion::MAX_ITEMS
      return render_errors([ "Exclua no máximo #{Ml::ItemDeletion::MAX_ITEMS} anúncios de uma vez." ], status: :unprocessable_content)
    end

    ids = expand_variations(ids)
    if ids.size > Ml::ItemDeletion::MAX_EXPANDED
      return render_errors([ "Com as variações, seriam #{ids.size} anúncios. Exclua no máximo #{Ml::ItemDeletion::MAX_EXPANDED} de uma vez." ], status: :unprocessable_content)
    end

    with_catalog = ActiveModel::Type::Boolean.new.cast(params[:with_catalog]) == true
    linked = Ml::ItemDeletion.linked_catalogs(Current.account, ids)
    if linked.any? && !with_catalog
      list = linked.map { |id, cats| "#{id} (catálogo #{cats.join(', ')})" }.join("; ")
      return render_errors([ "Anúncio sincronizado com catálogo: confirme a exclusão do catálogo junto (with_catalog=true). #{list}" ], status: :unprocessable_content)
    end

    Ml::OAuth.refresh!(Current.account)
    client = Ml::Client.new(access_token: Current.account.reload.access_token)
    results = Ml::ItemDeletion.call(client, Current.account, ids, user: Current.user, with_catalog: with_catalog).map(&:to_h)
    ok = results.count { |r| r[:ok] }
    message = ok == results.size ? "#{ok} anúncio(s) excluído(s) do Mercado Livre." : "#{ok} de #{results.size} anúncio(s) excluído(s). Veja os que o Mercado Livre recusou."
    render json: { ok: ok == results.size, message: message, results: results }
  rescue Ml::OAuth::Error
    render_errors([ "A conta do Mercado Livre precisa ser autorizada de novo." ], status: :unprocessable_content)
  end

  private

  def with_variations? = ActiveModel::Type::Boolean.new.cast(params[:with_variations]) == true

  def expand_variations(ids)
    with_variations? ? Painel::ListingFamilies.for(Current.account).expand(ids) : ids
  end

  # [{ item_id: pai selecionado, others: [outras variações] }] só dos que têm variações
  def variations_of(ids)
    return [] unless with_variations?

    families = Painel::ListingFamilies.for(Current.account)
    Array(ids).map(&:to_s).filter_map do |id|
      group = families.group_of(id)
      { item_id: id, others: group.item_ids - [ id ] } if group&.variations?
    end
  end
end
