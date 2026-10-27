# Seção Promoções (Central de Promoções do Mercado Livre).
# GET /api/promotions?account_id= → anúncios com promoção atual, melhor oferta e ganho; promoções da conta.
# GET /api/promotions/items/:item_id?account_id= → um anúncio com todas as ofertas e a margem de cada uma.
# PATCH /api/promotions/items/:item_id/settings?account_id= (admin) → margem mínima/máxima do anúncio (e do SKU).
# GET /api/promotions/export?account_id= → CSV com todas as promoções e anúncios (ativos e candidatos).
# POST /api/promotions/sync?account_id= (admin) → lê de novo a Central de Promoções.
class PromotionsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: %i[update_settings sync]

  def index
    render json: Painel::PromotionsQuery.call(Current.account, params)
  end

  def show
    render json: Painel::PromotionsQuery.detail(Current.account, params[:item_id])
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Anúncio não encontrado." ], status: :not_found)
  end

  def update_settings
    Painel::PromotionSettings.update(Current.account, params[:item_id], settings_params, Current.user)
    render json: Painel::PromotionsQuery.detail(Current.account, params[:item_id])
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Anúncio não encontrado." ], status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_entity)
  end

  def export
    send_data "﻿" + Painel::PromotionsQuery.export_csv(Current.account),
      filename: "promocoes-#{Time.zone.today.iso8601}.csv", type: "text/csv; charset=utf-8"
  end

  def sync
    Ml::PromotionsSyncJob.perform_later(Current.account.id)
    render json: { queued: true }, status: :accepted
  end

  private

  def settings_params
    params.permit(:min_margin_pct, :max_margin_pct, :apply_to_sku, :automation_enabled).to_h.symbolize_keys
  end
end
