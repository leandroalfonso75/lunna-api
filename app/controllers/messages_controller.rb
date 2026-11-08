# Seção Mensagens (pedido do usuário em 08/11/2026): conversas de pós-venda do Mercado Livre (só mensagens; as
# reclamações ficam na seção Reclamações) e resposta pelo Lunna. Respostas padrão: /api/question_templates?kind=mensagem.
# GET  /api/messages?account_id=&view=aguardando|todas&q=&page=  → conversas + contadores
# POST /api/messages/:pack_id/send?account_id=                    → envia ao comprador (admin; text, confirm: true)
class MessagesController < ApplicationController
  include CurrentAccount

  PER_PAGE = 20
  VIEWS = %w[aguardando todas].freeze

  before_action :require_admin!, only: [ :send_message ]

  rescue_from Ml::OAuth::Error do
    render_errors([ "A conta do Mercado Livre precisa ser autorizada de novo." ], status: :unprocessable_content)
  end

  def index
    view = VIEWS.include?(params[:view].to_s) ? params[:view].to_s : "aguardando"
    base = Current.account.ml_conversations.where("messages_count > 0")
    scope = view == "aguardando" ? base.where(last_from: "buyer") : base
    if (q = params[:q].to_s.strip).present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      packs = Current.account.ml_orders.where("buyer_nickname ILIKE :l OR buyer_name ILIKE :l OR order_id::text = :q OR pack_id::text = :q", l: like, q: q)
        .pluck(:pack_id, :order_id).map { |p, o| p || o }
      scope = scope.where("ml_conversations.messages::text ILIKE :l OR ml_conversations.pack_id::text = :q OR ml_conversations.pack_id IN (:packs)",
                          l: like, q: q, packs: packs.presence || [ 0 ])
    end
    page = [ params[:page].to_i, 1 ].max
    total = scope.count
    rows = scope.order(Arel.sql("last_from = 'buyer' DESC, last_message_at DESC NULLS LAST")).offset((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    orders = orders_for(rows.map(&:pack_id))

    render json: {
      view: view, total: total, page: page, per_page: PER_PAGE,
      counts: { aguardando: base.where(last_from: "buyer").count, todas: base.count },
      conversations: rows.map { |r| conversation_json(r, orders[r.pack_id] || []) }
    }
  end

  def send_message
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para enviar a mensagem no Mercado Livre." ], status: :unprocessable_content)
    end

    conv = Current.account.ml_conversations.find_by!(pack_id: params[:pack_id])
    text = params[:text].to_s.strip
    max = conv.seller_max_length.presence || 350
    return render_errors([ "Escreva a mensagem." ], status: :unprocessable_content) if text.blank?
    return render_errors([ "A mensagem pode ter no máximo #{max} caracteres (regra do Mercado Livre)." ], status: :unprocessable_content) if text.length > max
    unless conv.can_send?
      return render_errors([ "O Mercado Livre não deixa enviar mensagens nesta conversa (#{block_reason(conv)})." ], status: :unprocessable_content)
    end
    return render_errors([ "Comprador da conversa não identificado." ], status: :unprocessable_content) if conv.buyer_id.blank?

    log = Current.account.ml_message_sends.create!(pack_id: conv.pack_id, user: Current.user, text: text)
    client.send_pack_message(Current.account.seller_id, conv.pack_id, conv.buyer_id, text)
    log.update!(ok: true)
    Ml::Sync::Messages.refresh(client, Current.account, conv.pack_id)
    conv.reload
    render json: { ok: true, message: "Mensagem enviada ao comprador pelo Mercado Livre.",
                   conversation: conversation_json(conv, orders_for([ conv.pack_id ])[conv.pack_id] || []) }
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Conversa não encontrada." ], status: :not_found)
  rescue Ml::Client::Error => e
    log&.update!(ok: false, error: e.message.to_s.first(500))
    render_errors([ "O Mercado Livre recusou a mensagem: #{e.message.to_s.first(220)}" ], status: :unprocessable_content)
  end

  private

  def block_reason(conv) = MlConversation::SUBSTATUS_LABELS[conv.substatus] || conv.substatus.presence || "conversa bloqueada"

  def orders_for(packs)
    return {} if packs.empty?

    orders = Current.account.ml_orders.where(pack_id: packs).or(Current.account.ml_orders.where(order_id: packs)).includes(:ml_order_items).to_a
    orders.group_by { |o| packs.include?(o.pack_id) ? o.pack_id : o.order_id }
  end

  def conversation_json(r, orders)
    seller = Current.account.seller_id.to_i
    first = orders.min_by(&:date_created)
    { pack_id: r.pack_id, buyer_id: r.buyer_id, status: r.status, status_label: MlConversation::STATUS_LABELS[r.status] || r.status,
      block_reason: r.can_send? ? nil : block_reason(r), can_send: r.can_send?, awaiting: r.awaiting_seller?,
      claim_ids: r.claim_ids, unread: r.unread_count, last_message_at: r.last_message_at, max_length: r.seller_max_length.presence || 350,
      buyer: first && { nickname: first.buyer_nickname, name: first.try(:buyer_name) },
      order: first && { order_id: first.order_id, date: first.date_created, status: first.status, total: orders.sum { |o| o.total_amount.to_f }.round(2),
                        items: orders.flat_map(&:ml_order_items).map { |i| { item_id: i.item_id, title: i.title, quantity: i.quantity } }.first(5) },
      messages: Array(r.messages).map { |m| { id: m["id"], mine: m["from"].to_i == seller, text: m["text"], date: m["date"], read: m["read"],
                                              from: m["from"].to_i == seller ? "voce" : (m["from"].to_i == r.buyer_id.to_i ? "comprador" : "mercado_livre"),
                                              moderation: m["moderation"], attachments: m["attachments"] } } }
  end

  def client
    @client ||= begin
      Ml::OAuth.refresh!(Current.account)
      Ml::Client.new(access_token: Current.account.access_token)
    end
  end
end
