# Curva ABC (pedido do usuário em 07/11/2026): alterar título e ficha técnica pelo Lunna e "Ciente" nas sugestões.
# GET  /api/items/:item_id/title?account_id=            → título atual, se dá para trocar (e por quê) e o limite
# POST /api/items/:item_id/title/suggest?account_id=    → 5 títulos sugeridos pela IA (não publica)
# POST /api/items/:item_id/title?account_id=            → publica no ML (admin; text, confirm: true)
# GET  /api/items/:item_id/specs?account_id=            → campos da ficha técnica que faltam
# POST /api/items/:item_id/specs/suggest?account_id=    → valores sugeridos pela IA (não publica)
# POST /api/items/:item_id/specs?account_id=            → publica no ML (admin; values: {ID: {value_id, value_name}}, confirm: true)
# POST /api/items/:item_id/suggestion_acks?account_id=  → "Ciente" (key, kind: aplicada|aguardar)
# POST /api/items/:item_id/price?account_id=            → muda o preço no ML (admin; price, confirm: true)
# GET  /api/items/:item_id/variations?account_id=       → as outras variações do mesmo anúncio pai (Ml::ItemVariations)
# GET  /api/items/:item_id/model?account_id=            → Modelo e Modelo detalhado atuais, limite e buscas da categoria (14/11/2026)
# POST /api/items/:item_id/model/suggest?account_id=    → 3 opções de Modelo com palavras-chave + Modelo detalhado (IA; não publica)
# POST /api/items/:item_id/model?account_id=            → publica no ML (admin; model, detailed_model, confirm: true)
# GET  /api/items/:item_id/description?account_id=      → descrição atual
# POST /api/items/:item_id/description/suggest?...      → descrição mais chamativa (IA; não publica)
# POST /api/items/:item_id/description?account_id=      → publica no ML (admin; text, confirm: true)
# Modelo e descrição aceitam also_item_ids[]: outros anúncios do mesmo SKU escolhidos na confirmação (14/11/2026).
# Ciente, ficha técnica, preço, modelo e descrição aceitam apply_to_variations=true: valem também para as outras variações do anúncio pai.
class ItemEditsController < ApplicationController
  include CurrentAccount

  rescue_from Ml::OAuth::Error do
    render_errors([ "A conta do Mercado Livre precisa ser autorizada de novo." ], status: :unprocessable_content)
  end

  before_action :own_item!
  before_action :require_admin!, only: [ :publish_title, :publish_specs, :publish_price, :publish_model, :publish_description ]
  before_action :require_confirm!, only: [ :publish_title, :publish_specs, :publish_price, :publish_model, :publish_description ]

  def variations
    render json: Ml::ItemVariations.payload(Current.account, item_id)
  end

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
    others = result.ok && apply_to_variations? ? each_variation { |id| Ml::ItemSpecs.publish_shared(client, Current.account, id, values, user: Current.user) } : nil
    render json: { ok: result.ok, message: [ result.message, variations_message(others, "ficha técnica completada") ].compact.join(" "),
                   published: result.published, variations: others, errors: result.ok ? nil : [ result.message ] },
           status: result.ok ? :ok : :unprocessable_content
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def publish_price
    free = ActiveModel::Type::Boolean.new.cast(params[:free_shipping]) == true
    result = Ml::ItemPrice.publish(client, Current.account, item_id, params[:price], user: Current.user, free_shipping: free)
    others = result.ok && apply_to_variations? ? each_variation { |id| Ml::ItemPrice.publish(client, Current.account, id, params[:price], user: Current.user, free_shipping: free) } : nil
    render json: { ok: result.ok, message: [ result.message, variations_message(others, "preço aplicado") ].compact.join(" "),
                   price: result.price, variations: others, errors: result.ok ? nil : [ result.message ] },
           status: result.ok ? :ok : :unprocessable_content
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def model
    render json: Ml::ItemModelKeywords.info(client, Current.account, item_id)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def suggest_model
    info = Ml::ItemModelKeywords.info(client, Current.account, item_id)
    render json: Ai::ModelKeywordSuggestions.call(Current.account.company, info, description: description)
  rescue Ai::JsonChat::Error => e
    render_errors([ e.message ], status: :unprocessable_content)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def publish_model
    publish = ->(id) { Ml::ItemModelKeywords.publish(client, Current.account, id, model: params[:model], detailed_model: params[:detailed_model], user: Current.user) }
    result = publish.(item_id)
    others = result.ok && apply_to_variations? ? each_variation { |id| publish.(id) } : nil
    same = result.ok ? each_same_sku(others) { |id| publish.(id) } : nil
    render json: { ok: result.ok, message: [ result.message, variations_message(others, "modelo alterado"), same_sku_message(same, "modelo alterado") ].compact.join(" "),
                   model: result.model, detailed_model: result.detailed_model, variations: others, same_sku: same, errors: result.ok ? nil : [ result.message ] },
           status: result.ok ? :ok : :unprocessable_content
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def item_description
    render json: Ml::ItemDescription.info(client, Current.account, item_id)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def suggest_description
    info = Ml::ItemDescription.info(client, Current.account, item_id)
    render json: Ai::DescriptionSuggestion.call(Current.account.company, info, current: info[:current], questions: info[:questions])
  rescue Ai::JsonChat::Error => e
    render_errors([ e.message ], status: :unprocessable_content)
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def publish_description
    result = Ml::ItemDescription.publish(client, Current.account, item_id, params[:text], user: Current.user)
    others = result.ok && apply_to_variations? ? each_variation { |id| Ml::ItemDescription.publish(client, Current.account, id, params[:text], user: Current.user) } : nil
    same = result.ok ? each_same_sku(others) { |id| Ml::ItemDescription.publish(client, Current.account, id, params[:text], user: Current.user) } : nil
    render json: { ok: result.ok, message: [ result.message, variations_message(others, "descrição alterada"), same_sku_message(same, "descrição alterada") ].compact.join(" "),
                   length: result.length, variations: others, same_sku: same, errors: result.ok ? nil : [ result.message ] },
           status: result.ok ? :ok : :unprocessable_content
  rescue Ml::Client::Error => e
    ml_error(e)
  end

  def ack
    kind = params[:kind].to_s
    return render_errors([ "Escolha: aplicada, aguardar ou ignorar." ], status: :unprocessable_content) unless AbcSuggestionAck::KINDS.key?(kind) && kind != "feita"
    return render_errors([ "Sugestão não informada." ], status: :unprocessable_content) if params[:key].blank?

    ids = [ item_id ] + (apply_to_variations? ? Ml::ItemVariations.siblings(Current.account, item_id).pluck(:item_id) : [])
    ack = nil
    ids.each do |id|
      a = Current.account.abc_suggestion_acks.find_or_initialize_by(item_id: id, key: params[:key].to_s)
      a.update!(kind: kind, until_at: AbcSuggestionAck::KINDS[kind].from_now, user: Current.user)
      ack ||= a
    end
    message = case kind
    when "aguardar" then "A sugestão deixa de aparecer. Se nada mudar em 15 dias (#{I18n.l(ack.until_at.to_date, format: '%d/%m')}), ela volta."
    when "ignorar" then "Sugestão ignorada: nada muda no anúncio e ela não aparece até #{I18n.l(ack.until_at.to_date, format: '%d/%m')} (30 dias)."
    else "Marcada como aplicada no Mercado Livre. Quando os dados do anúncio forem relidos ela some; se ainda valer em 30 dias, volta."
    end
    message += " Vale também para as outras #{ids.size - 1} variação(ões) do anúncio." if ids.size > 1
    render json: { ok: true, message: message, until_at: ack.until_at, applied: ids.size }
  end

  private

  def item_id = params[:item_id].to_s

  def apply_to_variations? = ActiveModel::Type::Boolean.new.cast(params[:apply_to_variations]) == true

  # Publica em cada uma das outras variações do anúncio pai, uma a uma (escrita no ML, registrada em ml_item_edits);
  # a falha de uma não para as demais. => [{ item_id:, sku:, ok:, message: }]
  def each_variation
    Ml::ItemVariations.siblings(Current.account, item_id).order(:sku).pluck(:item_id, :sku).map do |id, sku|
      r = yield(id)
      same = r.message.to_s.start_with?("O anúncio já") # já estava com esse preço ou frete: nada a mudar
      { item_id: id, sku: sku, ok: r.ok || same, published: r.respond_to?(:published) ? r.published : nil, message: r.message }
    rescue Ml::Client::Error => e
      { item_id: id, sku: sku, ok: false, message: e.message.to_s.first(200) }
    end
  end

  # Outros anúncios do mesmo SKU escolhidos pelo usuário (also_item_ids[]); só os que são mesmo do mesmo SKU, sem repetir
  # os que já foram como variação. nil quando nenhum foi escolhido.
  def each_same_sku(done)
    wanted = Array(params[:also_item_ids]).map(&:to_s) - Array(done).map { |v| v[:item_id] }
    return nil if wanted.empty?

    Ml::ItemVariations.same_sku(Current.account, item_id).where(item_id: wanted).order(:item_id).pluck(:item_id, :sku).map do |id, sku|
      r = yield(id)
      { item_id: id, sku: sku, ok: r.ok, message: r.message }
    rescue Ml::Client::Error => e
      { item_id: id, sku: sku, ok: false, message: e.message.to_s.first(200) }
    end
  end

  def same_sku_message(list, what)
    return nil if list.nil?

    ok = list.count { |v| v[:ok] }
    "Outros anúncios do mesmo produto: #{what} em #{ok} de #{list.size}#{ok < list.size ? ' (veja os erros)' : ''}."
  end

  def variations_message(list, what)
    return nil if list.nil?
    return "Não há outras variações deste anúncio." if list.empty?

    ok = list.count { |v| v[:ok] }
    fail = list.size - ok
    "Outras variações: #{what} em #{ok} de #{list.size}#{fail.positive? ? " (#{fail} com erro: veja a lista)" : ''}."
  end

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
