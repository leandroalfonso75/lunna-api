# Seção Perguntas: importa as perguntas dos anúncios do vendedor (/questions/search, api_version 4), as mais novas
# primeiro, e grava status, texto e resposta. A cada rodada: as sem resposta inteiras e as mais recentes até encontrar
# uma página já conhecida e sem mudança; na primeira vez (ou 1x por dia), todas.
module Ml
  module Sync
    module Questions
      PAGE = 50
      MAX_PAGES = 40
      FULL_EVERY = 1.day

      Result = Struct.new(:count, :notes, keyword_init: true)

      def self.call(client, account, now: Time.current)
        full = account.questions_synced_at.nil? || account.questions_synced_at < now - FULL_EVERY
        notes = []
        count = 0
        count += read(client, account, status: "UNANSWERED", stop_when_known: false, notes: notes)
        count += read(client, account, status: nil, stop_when_known: !full, notes: notes)
        account.update_columns(questions_synced_at: now) if full && notes.empty?
        fill_askers(client, account, notes)
        Result.new(count: count, notes: notes)
      end

      ASKERS_BATCH = 60

      # Quem perguntou (pedido do usuário em 13/11/2026): o nome e o apelido da venda, se a pessoa já comprou da loja; senão
      # o apelido público do ML (GET /users/{id}). Sem resposta primeiro; até ASKERS_BATCH perguntas por rodada.
      def self.fill_askers(client, account, notes)
        rows = account.ml_questions.where(from_nickname: nil).where.not(from_id: nil)
                      .order(Arel.sql("CASE WHEN status = 'UNANSWERED' THEN 0 ELSE 1 END"), date_created: :desc).limit(ASKERS_BATCH).to_a
        return if rows.empty?

        buyers = account.ml_orders.where(buyer_id: rows.map(&:from_id).uniq).where.not(buyer_nickname: nil)
                        .order(date_created: :desc).pluck(:buyer_id, :buyer_nickname, :buyer_name)
                        .each_with_object({}) { |(id, nick, name), h| h[id] ||= [ nick, name ] }
        cache = {}
        rows.each do |q|
          nick, name = buyers[q.from_id]
          nick ||= (cache[q.from_id] ||= client.user(q.from_id)["nickname"].presence || "")
          q.update_columns(from_nickname: nick, from_name: name)
        end
      rescue Ml::Client::Error => e
        notes << "perguntas (quem perguntou): #{e.message.to_s.truncate(120)}"
      end

      def self.read(client, account, status:, stop_when_known:, notes:)
        count = 0
        MAX_PAGES.times do |page|
          data = client.questions_search(account.seller_id, offset: page * PAGE, limit: PAGE, status: status)
          rows = Array(data["questions"])
          changed = rows.count { |q| upsert(account, q) }
          count += rows.size
          break if rows.size < PAGE || (page + 1) * PAGE >= data["total"].to_i
          break if stop_when_known && changed.zero?
        end
        count
      rescue Ml::Client::Error => e
        notes << "perguntas: #{e.message.to_s.truncate(160)}"
        count
      end

      # Grava a pergunta; devolve true se é nova ou mudou (status ou resposta).
      def self.upsert(account, q)
        row = account.ml_questions.find_or_initialize_by(question_id: q["id"])
        attrs = attributes(q)
        return false if row.persisted? && attrs.slice(:status, :answer_text, :answer_status).all? { |k, v| row.public_send(k) == v }

        row.update!(attrs)
        true
      end

      def self.attributes(q)
        answer = q["answer"] || {}
        { item_id: q["item_id"], status: q["status"], text: q["text"], date_created: q["date_created"], from_id: q.dig("from", "id"),
          answer_text: answer["text"], answer_status: answer["status"], answer_date: answer["date_created"], hold: !!q["hold"], payload: q }
      end
    end
  end
end
