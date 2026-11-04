# Curva ABC > Fotos: gerar imagens do anúncio pela OpenRouter, aprovar e publicar no anúncio do Mercado Livre.
# GET   /api/items/:item_id/photos?account_id=        → fotos atuais do anúncio + pedidos recentes (sem os bytes)
# POST  /api/items/:item_id/photos?account_id=        → novo pedido (admin; count, instructions, reference_urls[], uploads[])
# GET   /api/photo_images/:id?account_id=             → a imagem (bytes)
# PATCH /api/photo_images/:id?account_id=             → aprovar/reprovar (admin; approved)
# POST  /api/photo_jobs/:id/publish?account_id=       → publica as aprovadas no ML (admin; confirm: true)
class PhotoJobsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :create, :approve, :publish ]

  MAX_UPLOAD_BYTES = 8.megabytes

  def index
    pictures = begin
      client.item_pictures(params[:item_id]).map { |p| { id: p["id"], url: p["secure_url"] || p["url"] } }
    rescue Ml::Client::Error, Ml::OAuth::Error
      []
    end
    jobs = Current.account.ml_photo_jobs.where(item_id: params[:item_id]).includes(:photos).order(created_at: :desc).limit(5)
    info = (client.item_info(params[:item_id]) rescue {})
    alternatives = info["catalog_listing"] ? (Ml::PicturePublisher.alternatives(client, Current.account.seller_id, params[:item_id]) rescue []) : []
    render json: { pictures: pictures, jobs: jobs.map { |j| job_json(j) }, ai_configured: Current.account.company.openrouter_api_key.present?,
                   catalog_listing: info["catalog_listing"] == true, alternatives: alternatives }
  end

  def create
    job = Current.account.ml_photo_jobs.new(
      item_id: params[:item_id], user: Current.user, count: params[:count].to_i, instructions: params[:instructions].to_s.strip.presence,
      reference_urls: Array(params[:reference_urls]).map(&:to_s).select { |u| u.start_with?("https://", "http://") },
      model: Current.account.company.ai_image_model
    )
    uploads = Array(params[:uploads]).map(&:to_s)
    MlPhotoJob.transaction do
      job.save!
      uploads.each_with_index do |data_url, i|
        m = data_url.match(%r{\Adata:(image/(?:png|jpeg|webp));base64,(.+)\z}m)
        raise ArgumentError, "Anexo #{i + 1}: envie uma imagem PNG, JPG ou WEBP." unless m

        bytes = Base64.decode64(m[2])
        raise ArgumentError, "Anexo #{i + 1}: imagem maior que 8 MB." if bytes.bytesize > MAX_UPLOAD_BYTES

        job.photos.create!(kind: "referencia", position: i, mime: m[1], data: bytes)
      end
    end
    Ai::PhotoGenerationJob.perform_later(job.id)
    render json: job_json(job.reload), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_content)
  rescue ArgumentError => e
    render_errors([ e.message ], status: :unprocessable_content)
  end

  def image
    photo = photo_scope.find(params[:id])
    send_data photo.data, type: photo.mime, disposition: "inline"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def approve
    photo = photo_scope.find(params[:id])
    photo.update!(approved: ActiveModel::Type::Boolean.new.cast(params[:approved]))
    render json: { id: photo.id, approved: photo.approved }
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Imagem não encontrada." ], status: :not_found)
  end

  def publish
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para publicar no Mercado Livre." ], status: :unprocessable_content)
    end

    job = Current.account.ml_photo_jobs.find(params[:id])
    result = Ml::PicturePublisher.call(job, client: client, target_item_id: params[:target_item_id], seller_id: Current.account.seller_id)
    render json: { ok: result.ok, message: result.message, errors: (result.ok ? nil : [ result.message ]), published: result.published,
                   alternatives: result.alternatives || [], job: job_json(job.reload) },
           status: result.ok ? :ok : :unprocessable_content
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Pedido não encontrado." ], status: :not_found)
  rescue Ml::OAuth::Error
    render_errors([ "A conta do Mercado Livre precisa ser autorizada de novo." ], status: :unprocessable_content)
  end

  private

  def client
    @client ||= begin
      Ml::OAuth.refresh!(Current.account)
      Ml::Client.new(access_token: Current.account.access_token)
    end
  end

  def photo_scope = MlGeneratedPhoto.joins(:ml_photo_job).where(ml_photo_jobs: { ml_account_id: Current.account.id })

  def job_json(job)
    {
      id: job.id, item_id: job.item_id, status: job.status, count: job.count, instructions: job.instructions,
      error: job.error, publish_error: job.publish_error, published_at: job.published_at, published_item_id: job.published_item_id,
      created_at: job.created_at,
      model: job.model, reference_urls: job.reference_urls,
      cost_usd: job.photos.sum { |p| p.cost_usd.to_f }.round(4),
      photos: job.photos.map { |p| { id: p.id, kind: p.kind, position: p.position, approved: p.approved, ml_picture_id: p.ml_picture_id, cost_usd: p.cost_usd&.to_f, model: p.model } }
    }
  end
end
