# Seção Produtos: remove produtos selecionados (pedido do usuário em 03/11/2026).
#   - keep_in_erp: true  → só some do Lunna (olist_products.hidden_at); o cadastro no Olist fica intacto e a sincronização
#                          não traz o produto de volta (o upsert não mexe em hidden_at);
#   - keep_in_erp: false → exclui o cadastro no Olist ERP (DELETE /produtos/{id}, API v3) e depois some do Lunna.
# Produto pai leva as variações junto (no Lunna; no Olist, excluir o pai exclui as variações). Cada exclusão no Olist
# fica em OlistChange (kind "delete", antes = descrição/SKU), gravada antes da chamada e fechada como done/failed;
# 404 do Olist conta como já excluído. Uma falha não impede as outras: o resultado traz o que deu certo e o que não.
module Olist
  class RemoveProducts
    Result = Struct.new(:removed, :failed, keyword_init: true)

    def self.call(company:, user:, olist_ids:, keep_in_erp:, client: nil)
      new(company, user, olist_ids, keep_in_erp, client).call
    end

    def initialize(company, user, olist_ids, keep_in_erp, client)
      @company = company
      @user = user
      @ids = Array(olist_ids).map(&:to_i).uniq
      @keep = keep_in_erp
      @client = client
    end

    def call
      products = @company.olist_products.where(olist_id: @ids, hidden_at: nil).to_a
      removed = []
      failed = []
      products.each do |product|
        if @keep
          hide(product)
          removed << payload(product)
        else
          error = delete_in_erp(product)
          if error
            failed << payload(product).merge(error: error)
          else
            hide(product, status: "E")
            removed << payload(product)
          end
        end
      end
      Result.new(removed: removed, failed: failed)
    end

    private

    def hide(product, status: nil)
      now = Time.current
      family = @company.olist_products.where(olist_id: product.olist_id).or(@company.olist_products.where(parent_olist_id: product.olist_id))
      attrs = { hidden_at: now, hidden_by_user_id: @user&.id, updated_at: now }
      attrs[:status] = status if status
      family.update_all(attrs)
    end

    # => nil quando excluiu (ou já não existia no Olist); mensagem de erro caso contrário.
    def delete_in_erp(product)
      change = OlistChange.create!(company_id: @company.id, user: @user, olist_product_id: product.olist_id, kind: "delete",
                                   before: { description: product.description, sku: product.sku, kind: product.kind,
                                             variations: product.variation_ids }, request: {}, status: "pending")
      begin
        client.delete_product(product.olist_id)
        change.update!(status: "done")
        nil
      rescue Olist::Client::NotFound
        change.update!(status: "done", error: "já não existia no Olist")
        nil
      rescue Olist::Client::Error, Olist::OAuth::Error => e
        change.update!(status: "failed", error: e.message.to_s.truncate(300))
        olist_message(e)
      end
    end

    def client
      @client ||= begin
        connection = @company.olist_connection
        raise Olist::OAuth::Error, "Olist ERP não conectado." if connection.nil? || connection.reauth_required?

        Olist::Client.new(connection)
      end
    end

    def olist_message(error)
      body = error.respond_to?(:body) ? error.body.to_s : ""
      detail = begin
        JSON.parse(body)["mensagem"].presence || JSON.parse(body)["message"].presence
      rescue JSON::ParserError, TypeError
        nil
      end
      "O Olist não excluiu#{detail ? ": #{detail}" : " (#{error.message.to_s.truncate(120)})"}"
    end

    def payload(product)
      { id: product.olist_id, sku: product.sku, description: product.description }
    end
  end
end
