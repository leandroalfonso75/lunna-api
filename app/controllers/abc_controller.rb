# GET /api/abc?account_id=&curve=all|A|B|C → resumo e linhas da Curva ABC (10.5)
# GET /api/abc/items/:id?account_id= → detalhe do anúncio na Curva ABC (10.6)
class AbcController < ApplicationController
  include CurrentAccount

  VALID_CURVES = %w[all A B C].freeze

  def index
    curve = params[:curve].to_s
    curve = "all" unless VALID_CURVES.include?(curve)

    render json: Abc::Report.call(Current.account, curve: curve)
  end

  def show
    # Confirma que o anúncio é desta conta antes de tudo (404 se não for) —
    # fora do universo da Curva ABC o detalhe ainda é respondido, com curva nil.
    Current.account.item_metrics.find_by!(item_id: params[:id])

    render json: Abc::Report.item(Current.account, params[:id])
  end
end
