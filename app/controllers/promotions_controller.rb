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
# PATCH /api/promotions/items/:item_id/automation?account_id= (admin) → "não automatizar promoções neste anúncio"
#   (enabled: false) ou volta a automatizar; apply_to_sku / apply_to_variations levam aos outros anúncios do produto.
# PATCH /api/promotions/items/:item_id/review_dismissed?account_id= (admin) → "Ciente, nada a ser feito": tira o anúncio
#   de "Para revisar" (dismissed: false desfaz). Aplicar, sair ou mudar os limites de um anúncio em "Para revisar" também
#   o tira da guia na hora.
# GET /api/promotions/actions?account_id= → histórico das ações nas promoções.
# GET /api/promotions/runs?account_id= → execuções da rotina das 03:00 (e simulações manuais), com os totais.
# POST /api/promotions/runs?account_id= (admin) → "Simular agora": roda a rotina em simulação, em fila.
# GET /api/promotions/runs/:id?account_id= → uma execução com o antes e o depois de cada anúncio.
# GET /api/promotions/runs/:id/export?account_id= → a mesma execução em CSV.
class PromotionsController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: %i[update_settings update_automation update_review_dismissed sync apply leave apply_best simulate dismiss_catalog_check]
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
    render json: dismiss_if_reviewing(Painel::PromotionsQuery.detail(Current.account, params[:item_id]))
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Anúncio não encontrado." ], status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_entity)
  end

  def update_automation
    bool = ActiveModel::Type::Boolean.new
    ids = Painel::PromotionSettings.set_automation(Current.account, params[:item_id], bool.cast(params[:enabled]) != false, Current.user,
      sku: bool.cast(params[:apply_to_sku]), variations: bool.cast(params[:apply_to_variations]))
    render json: Painel::PromotionsQuery.detail(Current.account, params[:item_id]).merge(updated: ids.size)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Anúncio não encontrado." ], status: :not_found)
  end

  def update_review_dismissed
    dismissed = ActiveModel::Type::Boolean.new.cast(params[:dismissed]) != false
    Painel::PromotionSettings.set_review_dismissed(Current.account, params[:item_id], dismissed, Current.user)
    render json: Painel::PromotionsQuery.detail(Current.account, params[:item_id])
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Anúncio não encontrado." ], status: :not_found)
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
    target = params[:promotion_type].present? ? params.permit(:promotion_id, :promotion_type, :price, :force).to_h.symbolize_keys : nil
    # "action" (aderir | editar_preco) vem no corpo, mas params[:action] é sempre o nome da ação do Rails ("apply"):
    # lido do corpo. Até 26/11/2026 lia params[:action], e todo "editar_preco" (cabível / mesmo assim na promoção
    # atual) voltava "Nenhuma oferta ... respeita a margem mínima" sem chegar ao Mercado Livre.
    target[:action] = (request.request_parameters["action"].presence || params[:offer_action]).to_s if target
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
    # em lote, os anúncios marcados como "não automatizar" ficam de fora (só mudam um a um, pela tela)
    ids -= Current.account.ml_promotion_settings.where(item_id: ids, automation_enabled: false).pluck(:item_id)
    # catálogo só entra no lote com "Incluir anúncios de catálogo na automação"
    ids -= Current.account.ml_items.where(item_id: ids, catalog_listing: true).pluck(:item_id) unless Current.account.company.promo_include_catalog
    return render_errors([ "Escolha os anúncios." ], status: :unprocessable_entity) if ids.empty?
    return render_errors([ "No máximo #{MAX_BATCH} anúncios por vez." ], status: :unprocessable_entity) if ids.size > MAX_BATCH

    Ml::PromotionsApplyJob.perform_later(Current.account.id, ids, Current.user&.id)
    render json: { queued: ids.size }, status: :accepted
  end

  # Aviso de catálogo para análise manual: marcar como visto.
  def dismiss_catalog_check
    Current.account.ml_catalog_checks.find(params[:id]).update!(status: "resolvido", message: "visto por #{Current.user&.name}")
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Aviso não encontrado." ], status: :not_found)
  end

  def actions
    render json: { actions: Painel::PromotionsQuery.actions(Current.account, params) }
  end

  def runs
    company = Current.account.company
    render json: {
      routine: { enabled: company.promo_routine_enabled, mode: company.promo_routine_mode },
      running: Current.account.ml_promotion_runs.exists?(status: "running"),
      runs: Painel::PromotionRunReport.list(Current.account)
    }
  end

  def simulate
    if Current.account.ml_promotion_runs.where(status: "running").where("started_at > ?", 30.minutes.ago).exists?
      return render_errors([ "Já tem uma execução da rotina em andamento." ], status: :conflict)
    end

    Ml::PromotionsRoutineJob.perform_later(Current.account.id, Current.user&.id)
    render json: { queued: true }, status: :accepted
  end

  def run
    render json: Painel::PromotionRunReport.detail(Current.account, params[:id])
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Execução não encontrada." ], status: :not_found)
  end

  def run_export
    run = Current.account.ml_promotion_runs.find(params[:id])
    send_data "﻿" + Painel::PromotionRunReport.csv(Current.account, run),
      filename: "rotina-promocoes-#{run.started_at.in_time_zone.strftime('%Y-%m-%d-%H%M')}.csv", type: "text/csv; charset=utf-8"
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Execução não encontrada." ], status: :not_found)
  end

  private

  def action_response(result)
    item = Painel::PromotionsQuery.detail(Current.account, params[:item_id])
    item = dismiss_if_reviewing(item) if result.ok
    { ok: result.ok, message: result.message, item: item }
  end

  # Qualquer ação que deu certo num anúncio de "Para revisar" (aplicar mesmo assim, a cabível, outro valor, sair, mudar os
  # limites) o tira da guia na hora, mesmo que ele continue fora das regras (pedido do usuário em 18/11/2026).
  def dismiss_if_reviewing(item)
    return item unless item.dig(:status, :key) == "para_revisar" && !item[:review_dismissed]

    Painel::PromotionSettings.set_review_dismissed(Current.account, params[:item_id], true, Current.user)
    item.merge(review_dismissed: true)
  end

  def settings_params
    params.permit(:limit_mode, :min_margin_pct, :max_margin_pct, :min_price, :max_price, :apply_to_sku, :apply_to_variations,
                  :automation_enabled, :rules_note).to_h.symbolize_keys
  end
end
