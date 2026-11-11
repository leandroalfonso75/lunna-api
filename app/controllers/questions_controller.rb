# Seção Perguntas (pedido do usuário em 08/11/2026): perguntas dos anúncios do Mercado Livre, resposta pelo Lunna e
# respostas padrão da empresa.
# GET    /api/questions?account_id=&view=sem_resposta|respondidas|todas&q=&page=  → lista + contadores
# POST   /api/questions/:id/answer?account_id=                                   → responde no ML (admin; text, confirm: true)
# DELETE /api/questions/:id?account_id=                                          → apaga a pergunta no ML (admin; confirm: true)
# POST   /api/questions/:id/suggest?account_id=                                  → resposta sugerida pela IA (não envia)
# GET    /api/question_templates?account_id=                                     → respostas padrão
# POST   /api/question_templates?account_id=                                     → inclui (admin; title, body)
# PATCH  /api/question_templates/:id?account_id=                                 → edita (admin)
# DELETE /api/question_templates/:id?account_id=                                 → exclui (admin)
class QuestionsController < ApplicationController
  include CurrentAccount

  PER_PAGE = 30
  MAX_TEXT = QuestionTemplate::MAX_BODY
  VIEWS = { "sem_resposta" => %w[UNANSWERED], "respondidas" => %w[ANSWERED], "todas" => nil }.freeze

  before_action :require_admin!, only: [ :answer, :destroy, :create_template, :update_template, :destroy_template ]

  rescue_from Ml::OAuth::Error do
    render_errors([ "A conta do Mercado Livre precisa ser autorizada de novo." ], status: :unprocessable_content)
  end

  def index
    view = VIEWS.key?(params[:view].to_s) ? params[:view].to_s : "sem_resposta"
    base = Current.account.ml_questions.where.not(status: "DELETED")
    scope = VIEWS[view] ? base.where(status: VIEWS[view]) : base
    if (q = params[:q].to_s.strip).present?
      ids = Current.account.ml_items.where("title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(q)}%").pluck(:item_id)
      scope = scope.where("ml_questions.text ILIKE :q OR ml_questions.answer_text ILIKE :q OR ml_questions.item_id = :id OR ml_questions.item_id IN (:ids)",
                          q: "%#{ActiveRecord::Base.sanitize_sql_like(q)}%", id: q.upcase, ids: ids.presence || [ "" ])
    end
    page = [ params[:page].to_i, 1 ].max
    total = scope.count
    rows = scope.order(Arel.sql("status = 'UNANSWERED' DESC, date_created DESC")).offset((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    items = Current.account.ml_items.where(item_id: rows.map(&:item_id).uniq).index_by(&:item_id)
    counts = base.group(:status).count

    render json: {
      view: view, total: total, page: page, per_page: PER_PAGE,
      counts: { sem_resposta: counts["UNANSWERED"].to_i, respondidas: counts["ANSWERED"].to_i, todas: counts.values.sum },
      synced_at: Current.account.questions_synced_at,
      questions: rows.map { |r| question_json(r, items[r.item_id]) }
    }
  end

  def answer
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para responder no Mercado Livre." ], status: :unprocessable_content)
    end

    question = Current.account.ml_questions.find_by!(question_id: params[:id])
    text = params[:text].to_s.strip
    return render_errors([ "Escreva a resposta." ], status: :unprocessable_content) if text.blank?
    return render_errors([ "A resposta pode ter no máximo #{MAX_TEXT} caracteres." ], status: :unprocessable_content) if text.length > MAX_TEXT
    return render_errors([ "Esta pergunta não está mais aguardando resposta (#{label(question.status)})." ], status: :unprocessable_content) unless question.answerable?

    log = Current.account.ml_question_answers.create!(question_id: question.question_id, user: Current.user, text: text)
    client.answer_question(question.question_id, text)
    log.update!(ok: true)
    fresh = (client.question(question.question_id) rescue nil)
    if fresh
      Ml::Sync::Questions.upsert(Current.account, fresh)
    else
      question.update!(status: "ANSWERED", answer_text: text, answer_date: Time.current, answer_status: "ACTIVE")
    end
    question.reload
    render json: { ok: true, message: "Resposta enviada ao Mercado Livre.", question: question_json(question, Current.account.ml_items.find_by(item_id: question.item_id)) }
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Pergunta não encontrada." ], status: :not_found)
  rescue Ml::Client::Error => e
    log&.update!(ok: false, error: e.message.to_s.first(500))
    render_errors([ "O Mercado Livre recusou a resposta: #{e.message.to_s.first(220)}" ], status: :unprocessable_content)
  end

  # Apaga a pergunta do anúncio no Mercado Livre (some para todos, inclusive com a resposta). Não dá para desfazer.
  def destroy
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_errors([ "Confirmação obrigatória: envie confirm=true para apagar a pergunta no Mercado Livre." ], status: :unprocessable_content)
    end

    question = Current.account.ml_questions.find_by!(question_id: params[:id])
    client.delete_question(question.question_id)
    question.update!(status: "DELETED")
    render json: { ok: true, message: "Pergunta apagada no Mercado Livre." }
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Pergunta não encontrada." ], status: :not_found)
  rescue Ml::Client::NotFound
    question.update!(status: "DELETED")
    render json: { ok: true, message: "A pergunta já não existia no Mercado Livre; tirada da lista." }
  rescue Ml::Client::Error => e
    render_errors([ "O Mercado Livre recusou apagar a pergunta: #{e.message.to_s.first(220)}" ], status: :unprocessable_content)
  end

  # Sugestão de resposta pela IA: dados do anúncio + respostas já dadas nele e nos anúncios do mesmo SKU.
  def suggest
    question = Current.account.ml_questions.find_by!(question_id: params[:id])
    item = Current.account.ml_items.find_by(item_id: question.item_id)
    answered = Current.account.ml_questions.where(status: "ANSWERED").where.not(answer_text: [ nil, "" ]).where.not(question_id: question.question_id)
    same_item = answered.where(item_id: question.item_id).order(date_created: :desc).limit(15).to_a
    skus = Painel::ItemSkus.for(Current.account, [ question.item_id ])[question.item_id] || []
    sibling_ids = skus.any? ? Painel::ItemSkus.items_with_skus(Current.account, skus) - [ question.item_id ] : []
    same_sku = sibling_ids.any? ? answered.where(item_id: sibling_ids).order(date_created: :desc).limit(15).to_a : []
    full = (client.item_full(question.item_id) rescue {})
    attributes = Array(full["attributes"]).filter_map { |a| "#{a['name']}: #{a['value_name']}" if a["value_name"].present? }.first(40).join("; ")
    description = (client.item_description(question.item_id)["plain_text"] rescue nil)

    tone = answered.order(date_created: :desc).limit(6).to_a
    pictures = Array(full["pictures"]).filter_map { |p| p["secure_url"] || p["url"] }.first(10)
    result = Ai::QuestionAnswerSuggestion.call(Current.account.company, question: question, item: item, description: description,
                                               same_item: same_item, same_sku: same_sku, attributes: attributes, tone: tone,
                                               pictures: pictures)
    render json: result.merge(used: { same_item: same_item.size, same_sku: same_sku.size, sku_items: sibling_ids.size, skus: skus, pictures: pictures.size })
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Pergunta não encontrada." ], status: :not_found)
  rescue Ai::JsonChat::Error => e
    render_errors([ e.message ], status: :unprocessable_content)
  end

  def templates
    render json: { templates: templates_scope.map { |t| template_json(t) } }
  end

  def create_template
    position = templates_scope.maximum(:position).to_i + 1
    t = templates_scope.create!(title: params[:title].to_s.strip, body: params[:body].to_s.strip, position: position)
    render json: template_json(t), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_content)
  end

  def update_template
    t = Current.account.company.question_templates.find(params[:id])
    t.update!(params.permit(:title, :body).to_h.transform_values { |v| v.to_s.strip })
    render json: template_json(t)
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Resposta padrão não encontrada." ], status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record.errors.full_messages, status: :unprocessable_content)
  end

  def destroy_template
    Current.account.company.question_templates.find(params[:id]).destroy!
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Resposta padrão não encontrada." ], status: :not_found)
  end

  private

  def label(status) = MlQuestion::STATUS_LABELS.dig(status, 0) || status

  # Respostas padrão por tipo: "pergunta" (padrão) ou "mensagem" (seção Mensagens).
  def templates_scope
    kind = QuestionTemplate::KINDS.key?(params[:kind].to_s) ? params[:kind].to_s : "pergunta"
    Current.account.company.question_templates.where(kind: kind)
  end

  def question_json(r, item)
    lbl, tone = MlQuestion::STATUS_LABELS.fetch(r.status, [ r.status, "neutral" ])
    { id: r.question_id, item_id: r.item_id, text: r.text, date_created: r.date_created, from_id: r.from_id,
      status: r.status, status_label: lbl, status_tone: tone, answerable: r.answerable?, hold: r.hold,
      answer: r.answer_text.present? ? { text: r.answer_text, date: r.answer_date, status: r.answer_status } : nil,
      item: item && { title: item.title, thumbnail: item.thumbnail, permalink: item.permalink, price: item.price&.to_f,
                      stock: item.available_quantity, status: item.status } }
  end

  def template_json(t) = { id: t.id, title: t.title, body: t.body, position: t.position, kind: t.kind }

  def client
    @client ||= begin
      Ml::OAuth.refresh!(Current.account)
      Ml::Client.new(access_token: Current.account.access_token)
    end
  end
end
