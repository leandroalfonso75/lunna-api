require "set"

# SPEC 8.6 — as 27 regras do motor de sugestões, na ordem da tabela (usada
# como desempate estável quando duas regras caem na mesma prioridade).
# `ctx` é um Abc::SuggestionEngine::Context: item (ml_item), metric
# (item_metrics), curve/group (da classificação — nil fora do universo),
# price (Abc::PriceSuggestion#call), conversion_median (Abc::Classifier),
# params (Abc::Params). Serviço puro.
module Abc
  class SuggestionEngine
    Context = Struct.new(:item, :metric, :curve, :group, :price, :conversion_median, :params, keyword_init: true)

    BANNED_TERMS = %w[
      frete\ gratis promocao oferta desconto barato imperdivel queima liquidacao
    ].freeze

    RULES = %i[
      rule_status_paused rule_moderation rule_stock_out rule_stock_coverage
      rule_price_reduce rule_price_increase rule_exposure_drop rule_conversion_drop
      rule_conversion_low_median rule_exposure_low rule_title_short rule_title_brand
      rule_title_model rule_policy_terms rule_attrs_required rule_attrs_main
      rule_photos_few rule_photos_low rule_video_missing rule_description_missing
      rule_description_short rule_listing_type_premium rule_free_shipping_range
      rule_logistic_full rule_quality_pending rule_strategy_liquidate rule_details_pending
    ].freeze

    def self.call(ctx) = new(ctx).call

    def initialize(ctx)
      @item = ctx.item
      @metric = ctx.metric
      @curve = ctx.curve
      @group = ctx.group
      @price = ctx.price
      @median = ctx.conversion_median
      @params = ctx.params
    end

    def call
      entries = RULES.flat_map { |rule| send(rule) }
      entries.each_with_index.sort_by { |suggestion, index| [ suggestion[:priority], index ] }.map(&:first)
    end

    private

    def status = @metric&.status.to_s
    def title = @metric&.title.to_s
    def full? = !!@metric&.full
    def stock = @metric&.stock.to_i
    def details_loaded? = @item&.details_checked_at.present?
    def normalize(text) = I18n.transliterate(text.to_s).downcase

    # 1 — Status: pausado que vendeu nos últimos 60 dias (30d atual + 30d
    # anterior) → reativar.
    def rule_status_paused
      return [] unless status == "paused"
      return [] unless @metric.units_30d.to_i + @metric.prev_units_30d.to_i > 0

      [ suggestion(1, "status", "Reativar anúncio", "Pausado, mas vendeu nos últimos 60 dias — reative para não perder vendas.") ]
    end

    # 2 — Moderação: em revisão.
    def rule_moderation
      return [] unless status == "under_review"

      [ suggestion(1, "moderação", "Resolver revisão do Mercado Livre", "Anúncio em revisão — resolva as pendências no painel do vendedor.") ]
    end

    # 3 — Estoque: ativo sem estoque.
    def rule_stock_out
      return [] unless status == "active" && stock.zero?

      title = full? ? "Programar envio ao Full" : "Repor estoque"
      [ suggestion(1, "estoque", title, "Estoque zerado em anúncio ativo — as vendas param até repor.") ]
    end

    # 4 — Estoque: cobertura 30d < 20 dias (só com estoque > 0).
    def rule_stock_coverage
      return [] unless stock.positive?

      coverage = @metric.coverage_30d
      return [] unless coverage.present? && coverage.to_f < 20

      priority = coverage.to_f < 10 ? 1 : 2
      [ suggestion(priority, "estoque", "Repor estoque em breve", "Cobertura de #{coverage.to_f.round(1)} dias — abaixo do recomendado (20 dias).") ]
    end

    # 5 — Preço sugerido abaixo do atual.
    def rule_price_reduce
      return [] unless @price[:kind] == "suggestion" && @price[:diff_pct].to_f < 0

      highest = @item&.price_ref && @item.price_ref["status"] == "with_benchmark_highest"
      low_conversion = @metric.conversion_30d.present? && @median.present? && @metric.conversion_30d.to_f < @median.to_f * 0.7
      priority = (highest || low_conversion) ? 1 : 2
      pct = @price[:diff_pct].to_f.abs.round(1)
      [ suggestion(priority, "preço", "Reduzir preço", "Preço #{pct}% acima da referência do Mercado Livre — considere reduzir.") ]
    end

    # 6 — Preço sugerido acima do atual.
    def rule_price_increase
      return [] unless @price[:kind] == "suggestion" && @price[:diff_pct].to_f > 0

      pct = @price[:diff_pct].to_f.round(1)
      [ suggestion(2, "preço", "Avaliar aumento de preço", "Preço sugerido #{pct}% acima do atual — há espaço para subir.") ]
    end

    # 7 — Exposição: curva A em queda e visitas 30d caíram > 15%.
    def rule_exposure_drop
      return [] unless @curve == "A" && @group == "down"

      visits = @metric.visits_30d.to_i
      prev_visits = @metric.prev_visits_30d.to_i
      return [] unless prev_visits.positive?
      return [] unless (visits - prev_visits).to_f / prev_visits * 100 < -15

      [ suggestion(1, "exposição", "Recuperar exposição", "Visitas caíram mais de 15% em 30 dias.") ]
    end

    # 8 — Conversão: curva A em queda e conversão < 80% da anterior.
    def rule_conversion_drop
      return [] unless @curve == "A" && @group == "down"

      conversion = @metric.conversion_30d
      prev_conversion = @metric.prev_conversion_30d
      return [] unless conversion.present? && prev_conversion.present? && prev_conversion.to_f.positive?
      return [] unless conversion.to_f < prev_conversion.to_f * 0.8

      [ suggestion(1, "conversão", "Investigar queda de conversão", "Conversão caiu mais de 20% em relação ao período anterior.") ]
    end

    # 9 — Conversão < 60% da mediana (ativo, ≥100 visitas, fora do grupo em queda).
    def rule_conversion_low_median
      return [] if @curve == "A" && @group == "down"
      return [] unless status == "active" && @metric.visits_30d.to_i >= 100
      return [] unless @metric.conversion_30d.present? && @median.present?
      return [] unless @metric.conversion_30d.to_f < @median.to_f * 0.6

      [ suggestion(2, "conversão", "Melhorar conversão", "Conversão abaixo de 60% da mediana da loja.") ]
    end

    # 10 — Exposição: ativo com < 60 visitas em 30d.
    def rule_exposure_low
      return [] unless status == "active" && @metric.visits_30d.to_i < 60

      priority = @curve == "C" ? 1 : 2
      [ suggestion(priority, "exposição", "Aumentar exposição", "Menos de 60 visitas em 30 dias.") ]
    end

    # 11 — Título com menos de 40 caracteres.
    def rule_title_short
      return [] unless title.length < 40

      [ suggestion(2, "título", "Ampliar título", "Título com menos de 40 caracteres — detalhe mais o produto.") ]
    end

    # 12 — Marca (quando houver) ausente no título.
    def rule_title_brand
      brand = @item&.brand.to_s.strip
      return [] if brand.blank?
      return [] if normalize(title).include?(normalize(brand))

      [ suggestion(2, "título", "Incluir marca no título", "A marca \"#{brand}\" não aparece no título.") ]
    end

    # 13 — Modelo (> 2 caracteres) ausente no título curto (< 55).
    def rule_title_model
      model = @item&.model.to_s.strip
      return [] if model.length <= 2
      return [] if title.length >= 55
      return [] if normalize(title).include?(normalize(model))

      [ suggestion(3, "título", "Incluir modelo no título", "O modelo \"#{model}\" não aparece no título.") ]
    end

    # 14 — Título com termos proibidos pela política do ML.
    def rule_policy_terms
      normalized = normalize(title)
      matched = BANNED_TERMS.select { |term| normalized.include?(term) }
      return [] if matched.empty?

      [ suggestion(1, "política", "Remover termos não permitidos do título", "Termos que violam a política do Mercado Livre: #{matched.join(', ')}.") ]
    end

    # 15 — Atributos obrigatórios faltando (detalhes precisam ter carregado).
    def rule_attrs_required
      return [] unless details_loaded?

      missing = Array(@item&.attrs_missing_required)
      return [] if missing.empty?

      [ suggestion(1, "ficha técnica", "Completar atributos obrigatórios", "Atributos obrigatórios faltando: #{missing.join(', ')}.") ]
    end

    # 16 — Características principais faltando.
    def rule_attrs_main
      return [] unless details_loaded?

      missing = Array(@item&.attrs_missing_main)
      return [] if missing.empty?

      [ suggestion(2, "ficha técnica", "Completar características principais", "Características principais faltando: #{missing.join(', ')}.") ]
    end

    # 17 — Menos de 3 fotos.
    def rule_photos_few
      pictures = @item&.pictures_count.to_i
      return [] unless pictures < 3

      [ suggestion(1, "fotos", "Adicionar fotos", "Apenas #{pictures} foto(s) — o mínimo recomendado é 6 a 10.") ]
    end

    # 18 — 3 a 5 fotos (meta 6-10).
    def rule_photos_low
      pictures = @item&.pictures_count.to_i
      return [] unless pictures.between?(3, 5)

      [ suggestion(2, "fotos", "Adicionar mais fotos", "#{pictures} fotos — a meta é 6 a 10.") ]
    end

    # 19 — Sem vídeo em curva A ou B.
    def rule_video_missing
      return [] if @item&.has_video
      return [] unless %w[A B].include?(@curve)

      [ suggestion(3, "vídeo", "Adicionar vídeo", "Sem vídeo no anúncio — ajuda a converter mais nas curvas A e B.") ]
    end

    # 20 — Sem descrição (detalhes carregados).
    def rule_description_missing
      return [] unless details_loaded?

      len = @item&.description_len.to_i
      return [] unless len.zero?

      [ suggestion(1, "descrição", "Escrever descrição", "Anúncio sem descrição.") ]
    end

    # 21 — Descrição < 400 caracteres (e não vazia — coberta pela regra 20).
    def rule_description_short
      return [] unless details_loaded?

      len = @item&.description_len.to_i
      return [] unless len.positive? && len < 400

      [ suggestion(2, "descrição", "Ampliar descrição", "Descrição com #{len} caracteres — a meta é pelo menos 400.") ]
    end

    # 22 — Clássico, preço ≥ 120, curva A/B e o ML recomenda parcelamento.
    def rule_listing_type_premium
      return [] unless @item&.listing_type_id == "gold_special"
      return [] unless @metric.price.to_f >= 120
      return [] unless %w[A B].include?(@curve)
      return [] unless installment_recommended?

      [ suggestion(3, "tipo de anúncio", "Testar anúncio Premium", "Preço alto e o Mercado Livre recomenda parcelamento — o tipo Premium pode ajudar.") ]
    end

    def installment_recommended?
      Array(@item&.quality_pending).any? do |entry|
        entry["key"].to_s.match?(/installment|parcel/i) || entry["title"].to_s.match?(/installment|parcel/i)
      end
    end

    # 23 — Sem frete grátis, preço entre R$ 60 (incl.) e R$ 79 (excl.).
    def rule_free_shipping_range
      return [] if @item&.free_shipping || @metric.free_shipping

      price = @metric.price.to_f
      return [] unless price >= 60 && price < 79

      [ suggestion(3, "frete", "Testar frete grátis", "Preço entre R$ 60 e R$ 79 sem frete grátis — o frete grátis pode aumentar as vendas.") ]
    end

    # 24 — Fora do Full, curva A, ≥ 30 vendas em 30d.
    def rule_logistic_full
      return [] if full?
      return [] unless @curve == "A" && @metric.units_30d.to_i >= 30

      [ suggestion(2, "logística", "Avaliar Full", "Curva A com #{@metric.units_30d.to_i} vendas em 30 dias fora do Full.") ]
    end

    # 25 — Cada recomendação pendente do ML (sem repetir "key").
    def rule_quality_pending
      score = @item&.quality_score.to_i
      seen = Set.new

      Array(@item&.quality_pending).filter_map do |entry|
        key = entry["key"]
        next nil if key.present? && !seen.add?(key)

        priority = score < 70 ? 2 : 3
        suggestion(priority, "qualidade", entry["title"].presence || "Ajustar qualidade do anúncio", entry["label"].presence || entry["title"].to_s)
      end
    end

    # 26 — Curva C, ativo, sem venda no mês, ≥ 60 visitas.
    def rule_strategy_liquidate
      return [] unless @curve == "C" && status == "active"
      return [] unless @metric.units_30d.to_i.zero? && @metric.visits_30d.to_i >= 60

      [ suggestion(2, "estratégia", "Avaliar liquidação ou unificação", "Curva C, sem vendas no mês e com #{@metric.visits_30d.to_i} visitas — considere liquidar ou unificar com outro anúncio.") ]
    end

    # 27 — Detalhes de cadastro ainda não carregados.
    def rule_details_pending
      return [] if details_loaded?

      [ suggestion(3, "dados", "Aguardar carregamento dos detalhes", "Detalhes de cadastro ainda não foram carregados pelo Mercado Livre.") ]
    end

    def suggestion(priority, area, title, why) = { priority: priority, area: area, title: title, why: why }
  end
end
