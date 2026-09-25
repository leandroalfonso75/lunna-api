# SPEC 8.5 — sugestão de preço a partir da referência do ML (`ml_items.price_ref`,
# jsonb com CHAVES STRING). `economics` é o `Abc::Economics::Result` já
# calculado pro preço atual (usa `unit[:fee]`/`unit[:shipping]` como base do
# fallback no preço sugerido). Serviço puro.
module Abc
  class PriceSuggestion
    ALIGNED_THRESHOLD = 0.5

    STATUS_TEXT = {
      "with_benchmark_highest" => "acima do preço de todos os concorrentes comparados",
      "with_benchmark_high" => "acima do preço de referência dos concorrentes",
      "no_benchmark_ok" => "alinhado ao preço de referência",
      "no_benchmark_lowest" => "abaixo da referência — o mais barato entre os comparados",
      "promotion_active" => "promoção sugerida ativa",
      "promotion_scheduled" => "promoção sugerida agendada",
      "not_optin_applied" => "promoção sugerida não aplicada"
    }.freeze

    ALIGNED_MESSAGE = "alinhado à referência"
    LOW_MARGIN_MESSAGE = "Abaixo da margem mínima"
    MAX_COST_MESSAGE = "tarifa, frete e imposto já consomem a margem mínima"

    def self.call(item:, metric:, economics:, cost:, params:) = new(item, metric, economics, cost, params).call

    def initialize(item, metric, economics, cost, params)
      @item = item
      @metric = metric
      @economics = economics
      @cost = cost
      @params = params
      @price_ref = item&.price_ref
    end

    def call
      kind = determine_kind
      base = { kind: kind, status_text: status_text, lowest: @price_ref && @price_ref["lowest"], competitors: competitors }

      return base.merge(empty_fields) unless %w[aligned suggestion].include?(kind)

      base.merge(suggestion_fields(kind))
    end

    private

    def has_cost? = !@cost.nil?

    def suggested = @price_ref && @price_ref["suggested"]

    def price = @metric.price.to_f

    def diff_pct
      return nil unless suggested.present? && suggested.to_f > 0 && price.positive?

      (suggested.to_f - price) / price * 100
    end

    def determine_kind
      return "loading" if @price_ref.blank? && @item&.details_checked_at.nil?
      return "none" unless suggested.present? && suggested.to_f > 0

      pct = diff_pct
      return "suggestion" if pct.nil?

      pct.abs < ALIGNED_THRESHOLD ? "aligned" : "suggestion"
    end

    def status_text = @price_ref && STATUS_TEXT[@price_ref["status"]]

    def competitors
      return [] unless @price_ref

      (@price_ref["graph"] || []).first(5).map { |entry| { price: entry["p"], title: entry["t"] } }
    end

    def empty_fields
      { suggested: nil, diff_pct: nil, fee: nil, shipping: nil, tax: nil, profit: nil, margin_pct: nil, max_cost: nil, low: nil, message: nil }
    end

    def suggestion_fields(kind)
      s = suggested.to_f
      fee = fee_at_suggested
      shipping = shipping_at_suggested
      tax = s * @params.tax_pct / 100.0

      fields = { suggested: s, diff_pct: diff_pct, fee: fee, shipping: shipping, tax: tax }
      fields.merge!(has_cost? ? with_cost_fields(kind, s, fee, shipping, tax) : without_cost_fields(kind, s, fee, shipping))
      fields
    end

    def with_cost_fields(kind, s, fee, shipping, tax)
      profit = s - fee - shipping - tax - @cost.to_f
      margin_pct = s.positive? ? (profit / s * 100) : nil
      low = margin_pct.present? && margin_pct < @params.min_margin_pct

      { profit: profit, margin_pct: margin_pct, max_cost: nil, low: low, message: message_for(kind, low ? LOW_MARGIN_MESSAGE : nil) }
    end

    def without_cost_fields(kind, s, fee, shipping)
      max_cost = s * (1 - @params.tax_pct / 100.0 - @params.min_margin_pct / 100.0) - fee - shipping

      { profit: nil, margin_pct: nil, max_cost: max_cost, low: nil, message: message_for(kind, max_cost <= 0 ? MAX_COST_MESSAGE : nil) }
    end

    def message_for(kind, warning) = kind == "aligned" ? ALIGNED_MESSAGE : warning

    # Tarifa/frete no sugerido: valor calculado no preço de referência
    # (fee_at_ref/ship_at_ref); sem ele, escala a tarifa atual pela razão
    # S ÷ P (tarifa) ou repete o frete atual (SPEC 8.5).
    def fee_at_suggested
      fee_at_ref = @item&.fee_at_ref
      return fee_at_ref.to_f if fee_at_ref.present?
      return @economics.unit[:fee] unless price.positive?

      @economics.unit[:fee] * (suggested.to_f / price)
    end

    def shipping_at_suggested
      ship_at_ref = @item&.ship_at_ref
      ship_at_ref.present? ? ship_at_ref.to_f : @economics.unit[:shipping]
    end
  end
end
