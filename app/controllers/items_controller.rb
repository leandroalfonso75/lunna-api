# GET  /api/items (SPEC 10.4) → tabela de anúncios com filtros, busca, ordenação e paginação (Painel::ItemQuery); traz a
#      curva ABC e a data de criação de cada anúncio e ordena por elas (sort=curve|date_created, 24/11/2026)
#      ?created_older_than=N (dias) → só anúncios criados há mais de N dias (também em /api/items/catalog)
# GET  /api/items/bulk_edit?item_ids[]=   → confere se os selecionados podem ser editados juntos (um só ou mesmos SKUs)
# POST /api/items/bulk_delete?account_id= → exclui do Mercado Livre (admin; item_ids[], confirm: true); resultado por anúncio
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

  def bulk_delete
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para excluir no Mercado Livre." ], status: :unprocessable_content)
    end

    ids = Array(params[:item_ids]).map(&:to_s).reject(&:blank?).uniq
    return render_errors([ "Selecione ao menos um anúncio." ], status: :unprocessable_content) if ids.empty?
    if ids.size > Ml::ItemDeletion::MAX_ITEMS
      return render_errors([ "Exclua no máximo #{Ml::ItemDeletion::MAX_ITEMS} anúncios de uma vez." ], status: :unprocessable_content)
    end

    Ml::OAuth.refresh!(Current.account)
    client = Ml::Client.new(access_token: Current.account.reload.access_token)
    results = Ml::ItemDeletion.call(client, Current.account, ids, user: Current.user).map(&:to_h)
    ok = results.count { |r| r[:ok] }
    message = ok == results.size ? "#{ok} anúncio(s) excluído(s) do Mercado Livre." : "#{ok} de #{results.size} anúncio(s) excluído(s). Veja os que o Mercado Livre recusou."
    render json: { ok: ok == results.size, message: message, results: results }
  rescue Ml::OAuth::Error
    render_errors([ "A conta do Mercado Livre precisa ser autorizada de novo." ], status: :unprocessable_content)
  end
end
