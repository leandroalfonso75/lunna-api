# Conexão do Olist ERP da empresa (somente leitura; nada aparece no painel ainda).
#   GET    /api/olist           → estado da conexão (logado)
#   POST   /api/olist/authorize → {url} para o admin autorizar no Olist
#   DELETE /api/olist           → desconecta (admin)
#   GET    /api/olist/products  → leitura de teste da integração (admin)
class OlistController < ApplicationController
  before_action :require_admin!, only: [ :authorize, :destroy, :products ]

  PRODUCT_FILTERS = %i[nome codigo gtin situacao dataCriacao dataAlteracao].freeze
  MAX_LIMIT = 100

  def show
    render json: { olist: payload(Current.company.olist_connection) }
  end

  def authorize
    unless Olist::OAuth.configured?
      return render_errors([ "Integração com o Olist ERP não configurada (OLIST_CLIENT_ID e OLIST_CLIENT_SECRET)." ], status: :unprocessable_content)
    end

    OlistOauthState.expired.delete_all
    state = OlistOauthState.create!(state: SecureRandom.uuid, company: Current.company, user: Current.user)

    render json: { url: Olist::OAuth.authorize_url(state.state) }
  end

  def destroy
    Current.company.olist_connection&.destroy!
    head :no_content
  end

  def products
    connection = Current.company.olist_connection
    return render_errors([ "Olist ERP não conectado." ], status: :unprocessable_content) if connection.nil? || connection.reauth_required?

    query = params.permit(*PRODUCT_FILTERS).to_h.symbolize_keys
    query[:limit] = [ params.fetch(:limit, 20).to_i, MAX_LIMIT ].min.clamp(1, MAX_LIMIT)
    query[:offset] = params.fetch(:offset, 0).to_i.clamp(0, 1_000_000)

    render json: Olist::Client.new(connection).products(query)
  rescue Olist::OAuth::Error, Olist::Client::Error => e
    Rails.logger.error("Olist products: #{e.class}")
    render_errors([ "Não foi possível consultar o Olist ERP agora." ], status: :bad_gateway)
  end

  private

  def payload(connection)
    return { configured: Olist::OAuth.configured?, connected: false } if connection.nil?

    {
      configured: Olist::OAuth.configured?,
      connected: connection.status == "active",
      status: connection.status,
      error: connection.last_error,
      connected_at: connection.created_at,
      connected_by: connection.connected_by_user&.name,
      access_expires_at: connection.expires_at,
      refresh_expires_at: connection.refresh_expires_at
    }
  end
end
