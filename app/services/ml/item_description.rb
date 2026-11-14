# Curva ABC > "Alterar descrição AGORA" (pedido do usuário em 14/11/2026): lê a descrição atual do anúncio, sugere uma
# versão mais chamativa (Ai::DescriptionSuggestion, com as perguntas dos compradores) e publica no ML
# (PUT /items/{id}/description, texto puro). Escrita: só admin, com confirmação, registrada em ml_item_edits ("descricao").
# Depois de publicar, as sugestões de descrição não voltam mais para o anúncio (pedido do usuário em 14/11/2026).
module Ml
  class ItemDescription
    Result = Struct.new(:ok, :message, :length, keyword_init: true)
    BOOST_KEY = "descrição:Deixar a descrição mais chamativa"
    KEYS = [ BOOST_KEY, "descrição:Escrever descrição", "descrição:Ampliar descrição" ].freeze
    MIN = 50
    MAX = 50_000

    def self.info(client, account, item_id) = new(client, account, item_id).info
    def self.publish(client, account, item_id, text, user:) = new(client, account, item_id).publish(text, user)

    def initialize(client, account, item_id)
      @client = client
      @account = account
      @item_id = item_id
    end

    def info
      @info ||= begin
        item = @client.item_full(@item_id)
        current = (@client.item_description(@item_id)["plain_text"].to_s rescue "")
        rule = item["catalog_listing"] ?
          { editable: false, reason: "Anúncio de catálogo: a descrição é a do produto do catálogo e o Mercado Livre não deixa trocar." } :
          { editable: true }
        { item_id: @item_id, title: item["title"], current: current, length: current.length, max_length: MAX,
          brand: attr(item, "BRAND"), model: attr(item, "MODEL"),
          attributes: Array(item["attributes"]).filter_map { |a| "#{a['name']}: #{a['value_name']}" if a["value_name"].present? }.first(40),
          questions: @account.ml_questions.where(item_id: @item_id).order(date_created: :desc).limit(15).pluck(:text).compact,
          **rule }
      end
    end

    def publish(text, user)
      text = Ai::DescriptionSuggestion.clean(text.to_s)
      data = info
      return Result.new(ok: false, message: data[:reason]) unless data[:editable]
      return Result.new(ok: false, message: "A descrição precisa ter pelo menos #{MIN} caracteres.") if text.length < MIN
      return Result.new(ok: false, message: "A descrição pode ter no máximo #{MAX} caracteres.") if text.length > MAX
      return Result.new(ok: false, message: "A descrição não pode ter links, e-mail ou telefone (regra do Mercado Livre).") if contact?(text)

      edit = @account.ml_item_edits.create!(item_id: @item_id, user: user, kind: "descricao",
                                            before: { text: data[:current].first(20_000) }, after: { text: text })
      @client.update_description(@item_id, text)
      edit.update!(ok: true)
      @account.ml_items.where(item_id: @item_id).update_all(description_len: text.length)
      AbcSuggestionAck.done!(@account, @item_id, KEYS, user: user) # descrição feita pelo Lunna: não sugere mais
      Result.new(ok: true, length: text.length, message: "Descrição alterada no Mercado Livre (#{text.length} caracteres).")
    rescue Ml::Client::Error => e
      edit&.update!(ok: false, error: e.message.to_s.first(2000))
      Result.new(ok: false, message: "O Mercado Livre recusou a alteração: #{Ml::ItemSpecs.ml_reason(e.message)}")
    end

    private

    def attr(item, id) = Array(item["attributes"]).find { |a| a["id"] == id }&.dig("value_name")

    def contact?(text)
      text.match?(%r{https?://|www\.|[\w.+-]+@[\w-]+\.\w+}i) || text.match?(/\(\d{2}\)\s?9?\d{4}[-\s]?\d{4}|\b\d{2}\s9?\d{4}-\d{4}\b/)
    end
  end
end
