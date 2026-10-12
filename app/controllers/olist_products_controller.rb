# Produtos do Olist guardados no Lunna (cópia local atualizada a cada 3 min) e
# alterações no Olist. Tudo escopado em Current.company.
#   GET   /api/olist/products            → lista (q, status, limit, offset)
#   GET   /api/olist/products/:id        → um produto (id = id do Olist)
#   PATCH /api/olist/products/:id/price  → altera preço no Olist (admin, confirm: true)
#   POST  /api/olist/products/:id/stock  → lança estoque no Olist (admin, confirm: true)
#   GET   /api/olist/changes             → registro das alterações feitas (admin)
class OlistProductsController < ApplicationController
  before_action :require_admin!, only: [ :update_price, :adjust_stock, :changes ]
  before_action :require_confirmation!, only: [ :update_price, :adjust_stock ]

  MAX_LIMIT = 100

  class NotConnected < StandardError; end

  rescue_from NotConnected do
    render_errors([ "Olist ERP não conectado." ], status: :unprocessable_content)
  end

  def index
    scope = Current.company.olist_products.search(params[:q])
    scope = scope.where(status: params[:status]) if params[:status].present?
    total = scope.count
    limit = params.fetch(:limit, 20).to_i.clamp(1, MAX_LIMIT)
    offset = params.fetch(:offset, 0).to_i.clamp(0, 10_000_000)

    render json: {
      products: scope.order(:description, :olist_id).limit(limit).offset(offset).map { |p| payload(p) },
      total: total, limit: limit, offset: offset,
      last_synced_at: Current.company.olist_products.maximum(:synced_at)
    }
  end

  def show
    render json: { product: payload(find_product) }
  end

  def update_price
    product = find_product
    change = changer(product).change_price(price: params[:price], promo_price: params[:promo_price])
    render json: { change: change_payload(change), product: payload(product.reload) }
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
    render json: { change: change_payload(change), product: payload(product.reload) }
  rescue Olist::ChangeProduct::Invalid => e
    render_errors([ e.message ], status: :unprocessable_content)
  rescue Olist::Client::Error, Olist::OAuth::Error => e
    render_olist_failure(e)
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

  def payload(product)
    {
      id: product.olist_id,
      sku: product.sku, description: product.description, kind: product.kind, status: product.status,
      variation_kind: product.variation_kind, unit: product.unit, gtin: product.gtin,
      price: product.price, promo_price: product.promo_price, cost_price: product.cost_price,
      avg_cost_price: product.avg_cost_price,
      stock: { balance: product.stock_balance, reserved: product.stock_reserved, available: product.stock_available,
               location: product.stock_location, deposits: product.stock_deposits },
      olist_created_at: product.olist_created_at, olist_updated_at: product.olist_updated_at,
      synced_at: product.synced_at
    }
  end

  def change_payload(change)
    {
      id: change.id, product_id: change.olist_product_id, kind: change.kind, status: change.status,
      before: change.before, request: change.request, error: change.error,
      changed_by: change.user&.name, changed_at: change.created_at
    }
  end
end
