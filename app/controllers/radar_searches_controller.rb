# /api/radar/searches — histórico de consultas do Radar ML, escopado em
# Current.company (consulta de outra empresa → 404). Guarda só os filtros e o
# resumo; reabrir uma consulta reaplica os filtros na tela.
class RadarSearchesController < ApplicationController
  LIST_LIMIT = 200

  def index
    searches = Current.company.radar_searches.recent.includes(:user).limit(LIST_LIMIT)
    render json: { searches: searches.map { |s| payload(s) } }
  end

  def show
    render json: { search: payload(find_search) }
  end

  def create
    search = Current.company.radar_searches.create!(create_params.merge(user: Current.user))
    render json: { search: payload(search) }, status: :created
  end

  private

  def find_search
    Current.company.radar_searches.recent.find(params[:id])
  end

  def create_params
    params.permit(:category_path, :data_ref, :total_items, :total_sold, :total_revenue, :median_price)
      .merge(filters: params.fetch(:filters, {}).permit!.to_h)
  end

  def payload(search)
    {
      id: search.id,
      category_path: search.category_path,
      filters: search.filters,
      data_ref: search.data_ref,
      total_items: search.total_items,
      total_sold: search.total_sold,
      total_revenue: search.total_revenue,
      median_price: search.median_price,
      searched_by: search.user&.name,
      searched_at: search.created_at
    }
  end
end
