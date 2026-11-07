# Curva ABC (pedido do usuário em 07/11/2026): alterar título e ficha técnica pelo Lunna e "Ciente" nas sugestões.
# GET  /api/items/:item_id/title?account_id=            → título atual, se dá para trocar (e por quê) e o limite
# POST /api/items/:item_id/title/suggest?account_id=    → 5 títulos sugeridos pela IA (não publica)
# POST /api/items/:item_id/title?account_id=            → publica no ML (admin; text, confirm: true)
# GET  /api/items/:item_id/specs?account_id=            → campos da ficha técnica que faltam
# POST /api/items/:item_id/specs/suggest?account_id=    → valores sugeridos pela IA (não publica)
# POST /api/items/:item_id/specs?account_id=            → publica no ML (admin; values: {ID: {value_id, value_name}}, confirm: true)
# POST /api/items/:item_id/suggestion_acks?account_id=  → "Ciente" (key, kind: aplicada|aguardar)
# POST /api/items/:item_id/price?account_id=            → muda o preço no ML (admin; price, confirm: true)
class ItemEditsController < ApplicationController
  include CurrentAccount

  rescue_from Ml::OAuth::Error do
    render_errors([ "A conta do Mercado Livre precisa ser autorizada de novo." ], status: :unprocessable_content)
  end

  before_action :own_item!
  before_action :require_admin!, only: [ :publish_title, :publish_specs, :publish_price ]
  before_action :require_confirm!, only: [ :publish_title, :publish_specs, :publish_price ]

  def title
    render json: Ml::ItemTitle.info(client, Current.account, item_id)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def suggest_title
    info = Ml::ItemTitle.info(client, Current.account, item_id)
    render json: { titles: Ai::TitleSuggestions.call(Current.account.company, info, description: description), max_length: info[:max_length] }
  rescue Ai::JsonChat::Error => e
    render_errors([ e.message ], status: :unprocessable_content)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def publish_title
    result = Ml::ItemTitle.publish(client, Current.account, item_id, params[:text], user: Current.user)
    render json: { ok: result.ok, message: result.message, title: result.title, errors: result.ok ? nil : [ result.message ] },
           status: result.ok ? :ok : :unprocessable_content
  end

  def specs
    render json: Ml::ItemSpecs.info(client, Current.account, item_id)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def suggest_specs
    info = Ml::ItemSpecs.info(client, Current.account, item_id)
    render json: { values: Ai::SpecSuggestions.call(Current.account.company, info, description: description) }
  rescue Ai::JsonChat::Error => e
    render_errors([ e.message ], status: :unprocessable_content)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def publish_specs
    values = params[:values].respond_to?(:to_unsafe_h) ? params[:values].to_unsafe_h : params[:values].to_h
    result = Ml::ItemSpecs.publish(client, Current.account, item_id, values, user: Current.user)
    render json: { ok: result.ok, message: result.message, published: result.published, errors: result.ok ? nil : [ result.message ] },
           status: result.ok ? :ok : :unprocessable_content
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def publish_price
    result = Ml::ItemPrice.publish(client, Current.account, item_id, params[:price], user: Current.user)
    render json: { ok: result.ok, message: result.message, price: result.price, errors: result.ok ? nil : [ result.message ] },
           status: result.ok ? :ok : :unprocessable_content
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def ack
    kind = params[:kind].to_s
    return render_errors([ "Escolha: aplicada ou aguardar." ], status: :unprocessable_content) unless AbcSuggestionAck::KINDS.key?(kind)
    return render_errors([ "Sugestão não informada." ], status: :unprocessable_content) if params[:key].blank?

    ack = Current.account.abc_suggestion_acks.find_or_initialize_by(item_id: item_id, key: params[:key].to_s)
    ack.update!(kind: kind, until_at: AbcSuggestionAck::KINDS[kind].from_now, user: Current.user)
    message = kind == "aguardar" ?
      "A sugestão deixa de aparecer. Se nada mudar em 15 dias (#{I18n.l(ack.until_at.to_date, format: '%d/%m')}), ela volta." :
      "Marcada como aplicada no Mercado Livre. Quando os dados do anúncio forem relidos ela some; se ainda valer em 30 dias, volta."
    render json: { ok: true, message: message, until_at: ack.until_at }
  end

  private

  def item_id = params[:item_id].to_s

  def own_item!
    return if Current.account.ml_items.exists?(item_id: item_id) || Current.account.item_metrics.exists?(item_id: item_id)

    render_errors([ "Anúncio não encontrado." ], status: :not_found)
  end

  def require_confirm!
    return if ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true

    render_errors([ "Confirmação obrigatória: envie confirm=true para publicar no Mercado Livre." ], status: :unprocessable_content)
  end

  def description
    (client.item_description(item_id)["plain_text"] rescue nil)
  end

  def ml_error(e) = render_errors([ "Não foi possível ler o anúncio no Mercado Livre: #{e.message.to_s.first(160)}" ], status: :bad_gateway)

  def client
    @client ||= begin
      Ml::OAuth.refresh!(Current.account)
      Ml::Client.new(access_token: Current.account.access_token)
    end
  end
end
