# Kit = 1 produto com variações + 1 produto simples (pedido do usuário em 26/11/2026). A partir do SKU do produto simples
# e do SKU pai do produto com variações (produtos do ERP sincronizados no Lunna):
#   - confere os dois (existe? o simples é simples? o pai tem variações?);
#   - lista as variações do pai (SKU, nome, EAN, custo) com o valor da variação tirado do fim da descrição
#     ("... - 220V" → 220V) e o tipo de variação deduzido dos valores (Voltagem, Cor, Tom, Tamanho; senão "Variação");
#   - devolve o preço cheio (preço de venda cadastrado, não o promocional) de cada um, base da sugestão de preço do kit.
# Não sugere SKU (27/11/2026, pedido do usuário): o Lunna poderá ser usado por outras lojas, e o padrão de SKU da loja
# piloto não vale para elas; os SKUs dos kits ficam para a pessoa preencher (ou pela planilha).
module Catalog
  class KitParts
    COLORS = %w[azul verde amarelo preto preta branco branca vermelho vermelha rosa roxo roxa lilas lilás cinza marrom bege
                laranja dourado dourada prata nude transparente vinho marinho caramelo creme off-white grafite].freeze
    SIZES = %w[pp p m g gg xg xgg eg u único unico].freeze

    def self.call(company, simple:, parent:) = new(company, simple, parent).call

    def initialize(company, simple, parent)
      @company = company
      @simple_sku = simple.to_s.strip
      @parent_sku = parent.to_s.strip
    end

    def call
      simple = check_simple
      parent, children = check_parent
      values = children.map { |c| c[:value] }
      { simple: simple, parent: parent, axis: axis_for(values), children: children }
    end

    private

    def products = @company.olist_products.where.not(status: "E")

    def info(p) = { sku: p.sku, name: p.description, gtin: p.gtin.presence, cost: (p.fifo_unit_cost || p.cost_price)&.to_f, price: p.price&.to_f }

    def check_simple
      return { sku: @simple_sku, ok: false, error: "Informe o SKU do produto simples." } if @simple_sku.blank?

      p = products.find_by(sku: @simple_sku)
      return { sku: @simple_sku, ok: false, error: "SKU não encontrado nos produtos do ERP." } unless p
      return info(p).merge(ok: false, error: "É um produto com variações (SKU pai). Informe-o na coluna ao lado.") if p.variation_kind == "P"
      return info(p).merge(ok: false, error: "É um kit, não um produto simples.") if p.kind == "K"

      info(p).merge(ok: true)
    end

    def check_parent
      return [ { sku: @parent_sku, ok: false, error: "Informe o SKU pai do produto com variações." }, [] ] if @parent_sku.blank?

      p = products.find_by(sku: @parent_sku)
      return [ { sku: @parent_sku, ok: false, error: "SKU não encontrado nos produtos do ERP." }, [] ] unless p
      if p.variation_kind != "P"
        parent = p.parent_olist_id && products.find_by(olist_id: p.parent_olist_id)
        hint = parent ? " Este SKU é uma variação de #{parent.sku}: informe o SKU pai." : " Informe o SKU pai de um produto com variações."
        return [ info(p).merge(ok: false, error: "Não é um produto com variações.#{hint}"), [] ]
      end

      kids = products.where(parent_olist_id: p.olist_id).order(:sku).to_a
      return [ info(p).merge(ok: false, error: "Este produto não tem variações cadastradas."), [] ] if kids.empty?

      [ info(p).merge(ok: true), kids.map { |k| info(k).merge(value: variation_value(p, k)) } ]
    end

    # "Secador ... - 220V" → "220V"; sem " - ", o que sobra depois do nome do pai; senão o fim do SKU
    def variation_value(parent, child)
      desc = child.description.to_s.strip
      tail = desc.split(/\s+-\s+/).last if desc.include?(" - ")
      tail ||= desc.delete_prefix(parent.description.to_s).strip.delete_prefix("-").strip.presence
      tail ||= child.sku.to_s.delete_prefix(parent.sku.to_s).delete_prefix("-")
      tail.to_s.strip.presence || child.sku
    end

    def axis_for(values)
      norm = values.map { |v| v.to_s.downcase.strip }
      return "Variação" if norm.empty?
      return "Voltagem" if norm.all? { |v| v.match?(/\A\d{2,3}\s*v\z/i) || v.match?(/bivolt/) }
      return "Cor" if norm.all? { |v| COLORS.include?(v.split.first.to_s) }
      return "Tamanho" if norm.all? { |v| SIZES.include?(v) }
      return "Tom" if norm.all? { |v| v.match?(/\A\d{2,4}\z/) }

      "Variação"
    end
  end
end
