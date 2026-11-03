# Produtos do Olist guardados no Lunna (cópia local atualizada a cada 3 min) e
# alterações no Olist. Tudo escopado em Current.company.
#   GET   /api/olist/products            → lista agrupada: pais com variações dentro (q, status, limit, offset)
#   GET   /api/olist/products/:id        → um produto (id = id do Olist)
#   PATCH /api/olist/products/:id/price  → altera preço no Olist (admin, confirm: true)
#   POST  /api/olist/products/:id/stock  → lança estoque no Olist (admin, confirm: true)
#   GET   /api/olist/changes             → registro das alterações feitas (admin)
#   POST  /api/olist/products/remove     → remove os selecionados (admin, confirm: true; ids, keep_in_erp):
#                                           mantém no Olist (só some do Lunna) ou exclui o cadastro no Olist
#   POST  /api/olist/products/restore    → traz de volta para a lista os ocultos (admin; ids). Excluído no Olist volta
#                                           como "Excluído" (o cadastro não é recriado no ERP)
#   GET   /api/olist/products?hidden=1   → lista só os ocultos
class OlistProductsController < ApplicationController
  before_action :require_admin!, only: [ :update_price, :adjust_stock, :changes, :remove, :restore ]
  before_action :require_confirmation!, only: [ :update_price, :adjust_stock, :remove ]
  MAX_REMOVE = 200

  MAX_LIMIT = 100

  class NotConnected < StandardError; end

  rescue_from NotConnected do
    render_errors([ "Olist ERP não conectado." ], status: :unprocessable_content)
  end

  # Lista só os produtos "de cima": normais e pais. Variação aparece dentro do pai
  # (`variations`); a busca acha o pai quando casa com uma variação dele.
  def index
    scope = listing_scope
    total = scope.count
    limit = params.fetch(:limit, 20).to_i.clamp(1, MAX_LIMIT)
    offset = params.fetch(:offset, 0).to_i.clamp(0, 10_000_000)

    render json: {
      products: payloads(scope.order(:description, :olist_id).limit(limit).offset(offset).to_a),
      total: total, limit: limit, offset: offset,
      hidden_count: Current.company.olist_products.where.not(hidden_at: nil).where(TOP_LEVEL_SQL).count,
      last_synced_at: Current.company.olist_products.maximum(:synced_at)
    }
  end

  def show
    render json: { product: payloads([ find_product ]).first }
  end

  def update_price
    product = find_product
    change = changer(product).change_price(price: params[:price], promo_price: params[:promo_price])
    render json: { change: change_payload(change), product: payloads([ product.reload ]).first }
  rescue Olist::ChangeProduct::Invalid => e
    render_errors([ e.message ], status: :unprocessable_content)
  rescue Olist::Client::Error, Olist::OAuth::Error => e
    render_olist_failure(e)
  end

  def adjust_stock
    product = find_product
    change = changer(product).change_stock(
      type: params[:type], quantity: params[:quantity], unit_price: params[:unit_price],
      note: params[:note], deposit_id: params[:deposit_id]
    )
    render json: { change: change_payload(change), product: payloads([ product.reload ]).first }
  rescue Olist::ChangeProduct::Invalid => e
    render_errors([ e.message ], status: :unprocessable_content)
  rescue Olist::Client::Error, Olist::OAuth::Error => e
    render_olist_failure(e)
  end

  # keep_in_erp é obrigatório e explícito (true/false): nunca exclui no Olist por omissão.
  def remove
    ids = Array(params[:ids]).map(&:to_s).select { |v| v.match?(/\A\d+\z/) }.first(MAX_REMOVE)
    return render_errors([ "Selecione ao menos um produto." ], status: :unprocessable_content) if ids.empty?
    unless %w[true false].include?(params[:keep_in_erp].to_s)
      return render_errors([ "Informe se o cadastro fica no ERP (keep_in_erp true ou false)." ], status: :unprocessable_content)
    end

    keep = params[:keep_in_erp].to_s == "true"
    raise NotConnected if !keep && (Current.company.olist_connection.nil? || Current.company.olist_connection.reauth_required?)

    result = Olist::RemoveProducts.call(company: Current.company, user: Current.user, olist_ids: ids, keep_in_erp: keep)
    render json: { removed: result.removed, failed: result.failed, kept_in_erp: keep }
  end

  # Traz de volta para a lista (produto e variações). Não mexe no Olist.
  def restore
    ids = Array(params[:ids]).map(&:to_s).select { |v| v.match?(/\A\d+\z/) }.first(MAX_REMOVE).map(&:to_i)
    return render_errors([ "Selecione ao menos um produto." ], status: :unprocessable_content) if ids.empty?

    scope = Current.company.olist_products
    products = scope.where(olist_id: ids).where.not(hidden_at: nil).to_a
    scope.where(olist_id: products.map(&:olist_id)).or(scope.where(parent_olist_id: products.map(&:olist_id)))
      .update_all(hidden_at: nil, hidden_by_user_id: nil, updated_at: Time.current)
    render json: { restored: products.map { |p| { id: p.olist_id, sku: p.sku, description: p.description, deleted_in_erp: p.status == "E" } } }
  end

  def changes
    list = Current.company.olist_changes.recent.includes(:user).limit(100)
    render json: { changes: list.map { |c| change_payload(c) } }
  end

  private

  def find_product
    Current.company.olist_products.find_by!(olist_id: params[:id])
  end

  def changer(product)
    connection = Current.company.olist_connection
    raise NotConnected if connection.nil? || connection.reauth_required?

    Olist::ChangeProduct.new(connection: connection, user: Current.user, product: product)
  end

  # Escrever no ERP exige confirmação explícita em cada chamada.
  def require_confirmation!
    return if ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true

    render_errors([ "Confirmação obrigatória: envie confirm=true para alterar dados no Olist." ], status: :unprocessable_content)
  end

  def render_olist_failure(error)
    Rails.logger.error("Olist change: #{error.class}")
    render_errors([ "O Olist não aceitou a alteração. Nada foi alterado no Lunna. Veja o registro de alterações." ], status: :bad_gateway)
  end

  def payloads(products)
    Olist::ProductPayloads.call(Current.company, products)
  end

  # Variação cujo pai existe fica fora da lista de cima (aparece dentro do pai).
  TOP_LEVEL_SQL = <<~SQL.squish.freeze
    NOT (olist_products.variation_kind = 'V' AND EXISTS (
      SELECT 1 FROM olist_products parent
      WHERE parent.company_id = olist_products.company_id AND parent.olist_id = olist_products.parent_olist_id))
  SQL

  def listing_scope
    all = Current.company.olist_products
    all = ActiveModel::Type::Boolean.new.cast(params[:hidden]) ? all.where.not(hidden_at: nil) : all.where(hidden_at: nil)
    top = all.where(TOP_LEVEL_SQL)

    if params[:q].present?
      matching = all.search(params[:q])
      parents_of_matches = matching.where.not(parent_olist_id: nil).select(:parent_olist_id)
      top = top.where(id: matching.select(:id)).or(top.where(olist_id: parents_of_matches))
    end

    params[:status].present? ? top.where(status: params[:status]) : top
  end

  def change_payload(change)
    {
      id: change.id, product_id: change.olist_product_id, kind: change.kind, status: change.status,
      before: change.before, request: change.request, error: change.error,
      changed_by: change.user&.name, changed_at: change.created_at
    }
  end
end
