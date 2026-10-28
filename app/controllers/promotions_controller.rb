# Seção Promoções (Central de Promoções do Mercado Livre).
# GET /api/promotions?account_id= → anúncios com promoção atual, melhor oferta e ganho; promoções da conta.
# GET /api/promotions/items/:item_id?account_id= → um anúncio com todas as ofertas e a margem de cada uma.
# PATCH /api/promotions/items/:item_id/settings?account_id= (admin) → limites do anúncio por margem ou por valor (e do
#   SKU e das variações do produto, se pedido).
# GET /api/promotions/export?account_id= → CSV com todas as promoções e anúncios (ativos e candidatos).
# POST /api/promotions/sync?account_id= (admin) → lê de novo a Central de Promoções.
# POST /api/promotions/items/:item_id/apply?account_id= (admin) → aplica no ML a melhor oferta (ou promotion_id +
#   promotion_type + action escolhidos); responde o resultado e o anúncio atualizado. also_sku / also_variations: leva
#   a mesma promoção, em fila, aos outros anúncios do SKU e das variações do produto.
# POST /api/promotions/items/:item_id/leave?account_id= (admin) → sai da promoção de preço atual.
# POST /api/promotions/apply_best?account_id= (admin) → aplica a melhor oferta em vários anúncios (item_ids), em fila.
# GET /api/promotions/actions?account_id= → histórico das ações nas promoções.
class PromotionsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: %i[update_settings sync apply leave apply_best]
  MAX_BATCH = 300

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

  def apply
    target = params[:promotion_type].present? ? params.permit(:promotion_id, :promotion_type, :action).to_h.symbolize_keys : nil
    result = Painel::PromotionActions.apply(Current.account, params[:item_id], user: Current.user, target: target)
    queued = 0
    if result.ok
      applied = target || (result.action && { promotion_id: result.action.to_promotion_id, promotion_type: result.action.to_type })
      # já estava na melhor: leva a promoção atual dele
      applied ||= Painel::PromotionsQuery.evaluate_item(Current.account, params[:item_id])[:current]
        &.then { |c| { promotion_id: c[:offer].promotion_id, promotion_type: c[:offer].promotion_type } }
      bool = ActiveModel::Type::Boolean.new
      queued = Painel::PromotionActions.extend_to_related(Current.account, params[:item_id], applied, user: Current.user,
        sku: bool.cast(params[:also_sku]), variations: bool.cast(params[:also_variations]))
    end
    message = queued.positive? ? "#{result.message} A mesma promoção foi enviada para mais #{queued} anúncios (veja o Histórico)." : result.message
    render json: action_response(result).merge(message: message, queued: queued)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Anúncio não encontrado." ], status: :not_found)
  end

  def leave
    result = Painel::PromotionActions.leave(Current.account, params[:item_id], user: Current.user)
    render json: action_response(result)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Anúncio não encontrado." ], status: :not_found)
  end

  def apply_best
    ids = Array(params[:item_ids]).map(&:to_s).uniq
    ids = Current.account.ml_items.where(item_id: ids).pluck(:item_id)
    return render_errors([ "Escolha os anúncios." ], status: :unprocessable_entity) if ids.empty?
    return render_errors([ "No máximo #{MAX_BATCH} anúncios por vez." ], status: :unprocessable_entity) if ids.size > MAX_BATCH

    Ml::PromotionsApplyJob.perform_later(Current.account.id, ids, Current.user&.id)
    render json: { queued: ids.size }, status: :accepted
  end

  def actions
    render json: { actions: Painel::PromotionsQuery.actions(Current.account, params) }
  end

  private

  def action_response(result)
    { ok: result.ok, message: result.message, item: Painel::PromotionsQuery.detail(Current.account, params[:item_id]) }
  end

  def settings_params
    params.permit(:limit_mode, :min_margin_pct, :max_margin_pct, :min_price, :max_price, :apply_to_sku, :apply_to_variations,
                  :automation_enabled, :rules_note).to_h.symbolize_keys
  end
end
