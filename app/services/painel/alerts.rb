# As 7 regras de "Precisa de atenção" (SPEC 7.5), como escopos SQL sobre
# item_metrics — fonte única, reutilizada pelo filtro `alert` de
# Painel::ItemQuery e pelo `alert_keys` de cada linha da tabela.
module Painel
  class Alerts
    Rule = Struct.new(:key, :title, :description, :severity, :scope, keyword_init: true)

    RULES = [
      Rule.new(
        key: "nostock", title: "Ativos sem estoque", description: "Anúncio ativo com estoque zerado.",
        severity: "bad", scope: ->(rel) { rel.where(status: "active", stock: 0) }
      ),
      Rule.new(
        key: "under_review", title: "Em revisão pelo Mercado Livre", description: "Anúncio em revisão pelo Mercado Livre.",
        severity: "bad", scope: ->(rel) { rel.where(status: "under_review") }
      ),
      Rule.new(
        key: "sales_drop", title: "Vendas caíram na semana", description: "Ativo com pelo menos 3 unidades a menos que a semana anterior.",
        severity: "bad", scope: ->(rel) { rel.where(status: "active").where("prev_units_7d - units_7d >= 3") }
      ),
      Rule.new(
        key: "low_coverage", title: "Estoque para menos de 14 dias", description: "Ativo com cobertura de estoque abaixo de 14 dias.",
        severity: "warn", scope: ->(rel) { rel.where(status: "active").where.not(coverage_days: nil).where("coverage_days < 14") }
      ),
      Rule.new(
        key: "visits_no_sales", title: "Visitas sem venda", description: "Ativo com 30 ou mais visitas na semana e nenhuma venda.",
        severity: "warn", scope: ->(rel) { rel.where(status: "active").where("visits_7d >= 30 AND units_7d = 0") }
      ),
      Rule.new(
        key: "low_quality", title: "Qualidade abaixo de 70", description: "Ativo com nota de qualidade abaixo de 70.",
        severity: "info", scope: ->(rel) { rel.where(status: "active").where("quality_score < 70") }
      ),
      Rule.new(
        key: "paused_selling", title: "Pausados que vendiam", description: "Pausado que tinha vendas na semana anterior.",
        severity: "info", scope: ->(rel) { rel.where(status: "paused").where("prev_units_7d > 0") }
      )
    ].freeze

    def self.call(metrics) = new(metrics).call

    def self.scope_for(key, metrics)
      RULES.find { |rule| rule.key == key }&.scope&.call(metrics)
    end

    # {item_id => [chaves dos alertas que ele dispara]}, restrito ao `metrics`
    # recebido (ex.: só os ids da página atual da tabela).
    def self.keys_by_item(metrics)
      keys = Hash.new { |h, k| h[k] = [] }
      RULES.each { |rule| rule.scope.call(metrics).pluck(:item_id).each { |id| keys[id] << rule.key } }
      keys
    end

    def initialize(metrics)
      @metrics = metrics
    end

    def call
      RULES.filter_map do |rule|
        matched = rule.scope.call(@metrics)
        count = matched.count
        next if count.zero?

        { key: rule.key, title: rule.title, description: rule.description, severity: rule.severity,
          count: count, item_ids: matched.pluck(:item_id) }
      end
    end
  end
end
