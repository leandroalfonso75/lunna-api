# /api/radar/collections — fila de pedidos de coleta do Radar ML, sempre escopada
# em Current.company (pedido de outra empresa → 404). Qualquer usuário da empresa
# pode pedir; o pedido só registra a intenção, a coleta roda sob comando do dono.
class RadarCollectionsController < ApplicationController
  def index
    render json: { collections: Current.company.radar_collections.recent.limit(100).map { |c| payload(c) } }
  end

  def create
    collection = Current.company.radar_collections.create!(
      category_path: params.require(:category_path),
      requested_by_user: Current.user
    )
    render json: { collection: payload(collection) }, status: :created
  end

  def destroy
    collection = Current.company.radar_collections.find(params[:id])
    unless collection.cancellable?
      return render_errors([ "Só dá para cancelar um pedido que ainda não começou a coletar." ], status: :unprocessable_content)
    end

    collection.destroy!
    head :no_content
  end

  private

  def payload(collection)
    {
      id: collection.id,
      category_path: collection.category_path,
      status: collection.status,
      error: collection.error,
      items_count: collection.items_count,
      requested_by: collection.requested_by_user&.name,
      requested_at: collection.created_at,
      started_at: collection.started_at,
      finished_at: collection.finished_at
    }
  end
end
