# Produtos cadastrados no Lunna ("Criar Produto com IA", 26/11/2026). Escopo: Current.company. Escrita só admin.
#   GET    /api/catalog_products                 → lista (q, status)
#   GET    /api/catalog_products/:id             → um produto (com as imagens de referência, sem os bytes)
#   POST   /api/catalog_products                 → cria o rascunho (kind obrigatório)
#   PATCH  /api/catalog_products/:id             → salva os campos
#   DELETE /api/catalog_products/:id             → exclui o rascunho (só no Lunna)
#   POST   /api/catalog_products/:id/generate    → a IA preenche o rascunho (replace: true troca os textos da IA)
#   POST   /api/catalog_products/:id/assets      → anexa imagem de referência (data URL)
#   GET    /api/catalog_product_assets/:id       → a imagem (bytes)
#   DELETE /api/catalog_product_assets/:id       → remove a imagem
#   GET    /api/catalog_products/sku_search      → busca SKUs para compor kits (produtos do ERP sincronizados no Lunna)
#   GET    /api/catalog_products/erp/:erp_id     → a ficha completa vinda do ERP de um produto (pelo id dele no ERP; a
#                                                   variação abre a ficha do pai), com estoque e custo PEPS da cópia
# A lista mostra os produtos criados no Lunna; ?source=erp lista os vindos do ERP (migração de 27/11/2026).
class CatalogProductsController < ApplicationController
  before_action :require_admin!, only: [ :create, :update, :destroy, :generate, :add_asset, :remove_asset ]
  before_action :set_product, only: [ :show, :update, :destroy, :generate, :add_asset ]

  EDITABLE = %i[
    name sku gtin unit price cost_price weight_net weight_gross package_width package_height package_length package_source
    stock_control initial_stock min_stock max_stock location preparation_days ncm cest icms_origin sped_item_type
    brand line model category condition sale_format description keywords seo_title seo_description video_url
    warranty supplier notes no_reference_skus use_component_references status
    kit_with_variations kit_simple_sku kit_simple_quantity kit_parent_sku kit_parent_quantity use_component_photos
  ].freeze
  JSON_FIELDS = %i[titles technical_sheet variation_axes variations kit_components common_components references regulatory].freeze

  def index
    scope = Current.company.catalog_products.order(updated_at: :desc).where(source: params[:source] == "erp" ? "erp" : "lunna")
    scope = scope.where(status: params[:status]) if CatalogProduct::STATUSES.include?(params[:status])
    if params[:q].present?
      q = "%#{CatalogProduct.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope = scope.where("name ILIKE :q OR sku ILIKE :q OR gtin ILIKE :q", q: q)
    end
    render json: { products: scope.limit(200).map { |p| summary(p) }, total: scope.count }
  end

  def show
    render json: detail(@product)
  end

  def by_erp
    erp_id = params[:erp_id].to_i
    parent = Current.company.olist_products.find_by(olist_id: erp_id)&.parent_olist_id
    product = Current.company.catalog_products.find_by(source: "erp", erp_id: [ erp_id, parent ].compact) ||
              Current.company.catalog_products.where(source: "erp").find_by("variations @> ?", [ { erp_id: erp_id } ].to_json)
    return render_errors([ "Este produto ainda não foi importado do ERP." ], status: :not_found) unless product

    render json: detail(product)
  end

  def create
    product = Current.company.catalog_products.new(product_params.merge(created_by: Current.user))
    product.kind = params[:kind].to_s
    product.sale_format = "kit" if product.kind == "kit" && !params.key?(:sale_format)
    product.save!
    render json: detail(product), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_content)
  end

  def update
    attrs = product_params
    # medidas digitadas na tela passam a ser do usuário (a IA não troca mais)
    if (%w[package_width package_height package_length weight_gross] & attrs.keys.map(&:to_s)).any? && !attrs.key?(:package_source)
      attrs[:package_source] = "usuario"
    end
    @product.update!(attrs)
    render json: detail(@product)
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_content)
  end

  def destroy
    @product.destroy!
    head :no_content
  end

  def generate
    Catalog::AiDraft.call(@product, replace: ActiveModel::Type::Boolean.new.cast(params[:replace]) == true)
    @product.save!
    render json: detail(@product)
  rescue Catalog::AiDraft::Error => e
    @product.update_columns(ai_error: e.message.truncate(250), updated_at: Time.current)
    render_errors([ e.message ], status: :unprocessable_content)
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_content)
  end

  def add_asset
    if @product.reference_images.size >= CatalogProduct::MAX_REFERENCE_IMAGES
      return render_errors([ "No máximo #{CatalogProduct::MAX_REFERENCE_IMAGES} imagens de referência." ], status: :unprocessable_content)
    end
    m = params[:data].to_s.match(%r{\Adata:(image/(?:png|jpeg|webp));base64,(.+)\z}m)
    return render_errors([ "Envie uma imagem PNG, JPG ou WEBP." ], status: :unprocessable_content) unless m

    bytes = Base64.decode64(m[2])
    return render_errors([ "Imagem maior que 8 MB." ], status: :unprocessable_content) if bytes.bytesize > CatalogProductAsset::MAX_BYTES

    asset = @product.assets.create!(kind: "referencia", mime: m[1], data: bytes, name: params[:name].to_s.first(120),
                                    position: @product.assets.maximum(:position).to_i + 1)
    render json: asset_json(asset), status: :created
  end

  def asset
    a = asset_scope.find(params[:id])
    send_data a.data, type: a.mime, disposition: "inline"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def remove_asset
    asset_scope.find(params[:id]).destroy!
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Imagem não encontrada." ], status: :not_found)
  end

  # Kit = 1 produto com variações + 1 produto simples: confere os dois SKUs, lista as variações do pai e sugere os SKUs.
  #   GET /api/catalog_products/kit_parts?simple=LS-DIF&parent=LS-SCN01
  def kit_parts
    render json: Catalog::KitParts.call(Current.company, simple: params[:simple], parent: params[:parent])
  end

  # Produtos do ERP (sincronizados no Lunna) para compor kits: SKU, nome, EAN, preço, custo. Variação-pai fica de fora
  # (não é vendável); kits entram (um kit pode ter outro kit). Neutro de ERP: hoje a fonte é o Olist.
  def sku_search
    q = params[:q].to_s.strip
    return render json: { items: [] } if q.size < 2

    like = "%#{OlistProduct.sanitize_sql_like(q)}%"
    rows = Current.company.olist_products.where(hidden_at: nil).where.not(status: "E").where.not(variation_kind: "P")
                  .where.not(sku: [ nil, "" ]).where("sku ILIKE :q OR description ILIKE :q OR gtin ILIKE :q", q: like)
                  .order(Arel.sql("CASE WHEN sku ILIKE #{OlistProduct.connection.quote("#{q}%")} THEN 0 ELSE 1 END"), :description).limit(15)
    render json: { items: rows.map { |p| { sku: p.sku, name: p.description, gtin: p.gtin, unit: p.unit, price: p.price&.to_f,
                                           cost: (p.fifo_unit_cost || p.cost_price)&.to_f, kit: p.kind == "K", source: "erp" } } }
  end

  private

  def set_product
    @product = Current.company.catalog_products.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Produto não encontrado." ], status: :not_found)
  end

  def asset_scope = CatalogProductAsset.joins(:catalog_product).where(catalog_products: { company_id: Current.company.id })

  def product_params
    attrs = params.permit(*EDITABLE).to_h.symbolize_keys
    JSON_FIELDS.each do |field|
      next unless params.key?(field)

      raw = params[field]
      attrs[field] = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw.is_a?(Array) ? raw.map { |x| x.respond_to?(:to_unsafe_h) ? x.to_unsafe_h : x } : raw)
    end
    attrs
  end

  def summary(p)
    { id: p.id, kind: p.kind, status: p.status, name: p.name, sku: p.sku, price: p.price&.to_f,
      variations_count: p.variations.size, components_count: p.kit_components.size, updated_at: p.updated_at,
      ai_generated_at: p.ai_generated_at, review_count: p.ai_review.size, exported: p.erp_exports.present? }
  end

  def detail(p)
    p.as_json(except: %w[company_id]).merge(
      "assets" => p.assets.map { |a| asset_json(a) },
      "components_info" => components_info(p),
      "erp_stock" => p.from_erp? ? Erp::CatalogStock.call(Current.company, p) : nil,
      "erp_name" => p.from_erp? ? (p.erp_key == "olist" ? "Olist" : p.erp_key) : nil
    )
  end

  def asset_json(a) = { id: a.id, kind: a.kind, name: a.name, mime: a.mime, variation_key: a.variation_key, position: a.position }

  # nome e custo dos SKUs usados como componentes (para a tela mostrar e somar o custo do kit)
  def components_info(p)
    skus = (p.kit_components + p.common_components + p.variations.flat_map { |v| Array(v["components"]) }).map { |c| c["sku"] }.uniq
    return {} if skus.empty?

    Current.company.olist_products.where(sku: skus).where.not(status: "E").order(:updated_at).each_with_object({}) do |o, h|
      h[o.sku] = { name: o.description, cost: (o.fifo_unit_cost || o.cost_price)&.to_f, price: o.price&.to_f, gtin: o.gtin }
    end
  end
end
