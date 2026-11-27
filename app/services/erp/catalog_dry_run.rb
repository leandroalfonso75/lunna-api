require "csv"

# Ensaio da migração dos produtos do ERP (27/11/2026): lê no ERP o cadastro de cada produto ativo e mostra o que viria
# para a ficha do Lunna, SEM gravar nada (nem baixar imagens). E o relatório dos inativos/excluídos e dos removidos da
# lista do Lunna, que não são importados (o usuário decide depois).
module Erp
  class CatalogDryRun
    HEADER = %w[id_erp sku nome tipo variacoes variacoes_kit componentes fotos ncm gtin marca categoria medidas peso descricao avisos].freeze

    def initialize(company, client: nil, sleeper: ->(s) { sleep(s) })
      @company = company
      @client = client || Olist::Client.new(company.olist_connection)
      @sleeper = sleeper
    end

    # => { rows: [...], summary: {...}, csv: "..." }
    def call
      tops = @company.olist_products.where(parent_olist_id: nil, status: "A", hidden_at: nil).order(:description)
      kit_children = @company.olist_products.where(kind: "K").where.not(parent_olist_id: nil).pluck(:olist_id).to_set
      rows = tops.map do |top|
        payload = @client.product(top.olist_id)
        children = Array(payload["variacoes"]).select { |v| kit_children.include?(v["id"]) }.to_h { |v| [ v["id"], @client.product(v["id"]) ] }
        mapped = OlistProductMapper.call(payload, children: children)
        row(top, mapped)
      rescue StandardError => e
        { id_erp: top.olist_id, sku: top.sku, nome: top.description, tipo: "erro", avisos: "não lido: #{e.message.truncate(120)}" }
      ensure
        @sleeper.call(1.0) # o ERP limita as chamadas por minuto (no ensaio de 27/11, 4 respostas 429 com 0,3 s)
      end
      { rows: rows, summary: summary(rows), csv: to_csv(rows) }
    end

    # Inativos/excluídos no ERP e removidos da lista do Lunna (não importados). Diz se o SKU é componente de algum kit ativo.
    def self.excluded_report(company)
      kits = company.olist_products.where(status: "A").where.not(kit_components: []).pluck(:sku, :kit_components)
      used_in = ->(sku) { kits.select { |_, comps| Array(comps).any? { |c| (c["sku"] || c.dig("produto", "sku")) == sku } }.map(&:first) }
      rows = company.olist_products.where("status <> 'A' OR hidden_at IS NOT NULL").order(:description).map do |p|
        { id_erp: p.olist_id, sku: p.sku, nome: p.description, situacao_erp: { "A" => "ativo", "I" => "inativo", "E" => "excluído" }.fetch(p.status, p.status),
          removido_no_lunna: p.hidden_at ? "sim" : "não", tipo: { "S" => "simples", "V" => "com variações", "K" => "kit" }.fetch(p.kind, p.kind),
          variacao_de: p.parent_olist_id, estoque_disponivel: p.stock_available&.to_f, componente_de_kits_ativos: used_in.(p.sku).join(" ") }
      end
      csv = CSV.generate(col_sep: ";") { |c| c << rows.first&.keys&.map(&:to_s).to_a; rows.each { |r| c << r.values } }
      { rows: rows, csv: csv }
    end

    private

    def row(top, mapped)
      a = mapped[:attrs]
      vars = Array(a[:variations])
      { id_erp: top.olist_id, sku: a[:sku], nome: a[:name], tipo: a[:kind], variacoes: vars.size, variacoes_kit: vars.count { |v| v["kit"] },
        componentes: Array(a[:kit_components]).size, fotos: mapped[:images].size, ncm: a[:ncm].present? ? "sim" : "não",
        gtin: a[:gtin].present? ? "sim" : "não", marca: a[:brand].present? ? "sim" : "não", categoria: a[:category].present? ? "sim" : "não",
        medidas: a[:package_source] ? "sim" : "não", peso: a[:weight_gross] || a[:weight_net] ? "sim" : "não",
        descricao: a[:description].present? ? "sim" : "não", avisos: mapped[:warnings].join(" | ") }
    end

    def summary(rows)
      ok = rows.reject { |r| r[:tipo] == "erro" }
      {
        produtos: rows.size, simples: ok.count { |r| r[:tipo] == "simple" }, com_variacoes: ok.count { |r| r[:tipo] == "variations" },
        kits: ok.count { |r| r[:tipo] == "kit" }, variacoes: ok.sum { |r| r[:variacoes] }, variacoes_kit: ok.sum { |r| r[:variacoes_kit] },
        fotos: ok.sum { |r| r[:fotos] }, sem_fotos: ok.count { |r| r[:fotos].zero? }, sem_ncm: ok.count { |r| r[:ncm] == "não" },
        sem_gtin: ok.count { |r| r[:gtin] == "não" }, sem_marca: ok.count { |r| r[:marca] == "não" }, sem_medidas: ok.count { |r| r[:medidas] == "não" },
        sem_peso: ok.count { |r| r[:peso] == "não" }, sem_descricao: ok.count { |r| r[:descricao] == "não" },
        com_avisos: ok.count { |r| r[:avisos].present? }, erros: rows.count { |r| r[:tipo] == "erro" }
      }
    end

    def to_csv(rows)
      CSV.generate(col_sep: ";") do |c|
        c << HEADER
        rows.each { |r| c << HEADER.map { |h| r[h.to_sym] } }
      end
    end
  end
end
