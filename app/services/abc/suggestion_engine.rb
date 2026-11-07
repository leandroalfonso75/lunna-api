require "set"

# SPEC 8.6 — as 27 regras do motor de sugestões, na ordem da tabela (usada
# como desempate estável quando duas regras caem na mesma prioridade).
# `ctx` é um Abc::SuggestionEngine::Context: item (ml_item), metric
# (item_metrics), curve/group (da classificação — nil fora do universo),
# price (Abc::PriceSuggestion#call), conversion_median (Abc::Classifier),
# params (Abc::Params). Serviço puro.
module Abc
  class SuggestionEngine
    Context = Struct.new(:item, :metric, :curve, :group, :price, :conversion_median, :params, :economics, :in_ads, :title_rule,
                         keyword_init: true)

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
      @unit = ctx.economics&.unit
      @in_ads = ctx.in_ads
      @title_rule = ctx.title_rule || { editable: true }
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

    # O ML só deixa trocar o título de anúncio sem venda (modelo User Products: nenhum anúncio do mesmo produto vendeu)
    # e fora do catálogo. Sem poder trocar, as sugestões de título não aparecem (pedido do usuário em 07/11/2026).
    def title_editable? = @title_rule[:editable] != false
    def title_action = { kind: "alterar_titulo" }

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
      [ suggestion(priority, "preço", "Reduzir preço", "Preço #{pct}% acima da referência do Mercado Livre — considere reduzir.",
                   options: price_options, calculator: price_calculator) ]
    end

    # 6 — Preço sugerido acima do atual.
    def rule_price_increase
      return [] unless @price[:kind] == "suggestion" && @price[:diff_pct].to_f > 0

      pct = @price[:diff_pct].to_f.round(1)
      [ suggestion(2, "preço", "Avaliar aumento de preço",
                   "Você está #{pct}% abaixo do preço de referência do Mercado Livre (o preço que ele considera competitivo frente "                    "a anúncios parecidos). Dá para subir até a referência e ganhar margem sem deixar de ser competitivo; "                    "não é para ganhar exposição — acima da referência a exposição pode cair.",
                   options: price_options, calculator: price_calculator) ]
    end

    # 7 — Exposição: curva A em queda e visitas 30d caíram > 15%.
    def rule_exposure_drop
      return [] unless @curve == "A" && @group == "down"

      visits = @metric.visits_30d.to_i
      prev_visits = @metric.prev_visits_30d.to_i
      return [] unless prev_visits.positive?
      return [] unless (visits - prev_visits).to_f / prev_visits * 100 < -15

      [ suggestion(1, "exposição", "Recuperar exposição", "Visitas caíram mais de 15% em 30 dias.", steps: exposure_steps) ]
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
      [ suggestion(priority, "exposição", "Aumentar exposição", "Menos de 60 visitas em 30 dias.", steps: exposure_steps) ]
    end

    # 11 — Título com menos de 40 caracteres.
    def rule_title_short
      return [] unless title_editable? && title.length < 40

      [ suggestion(2, "título", "Ampliar título", "Título com menos de 40 caracteres — detalhe mais o produto.", action: title_action) ]
    end

    # 12 — Marca (quando houver) ausente no título.
    def rule_title_brand
      return [] unless title_editable?

      brand = @item&.brand.to_s.strip
      return [] if brand.blank?
      return [] if normalize(title).include?(normalize(brand))

      [ suggestion(2, "título", "Incluir marca no título", "A marca \"#{brand}\" não aparece no título.", action: title_action) ]
    end

    # 13 — Modelo (> 2 caracteres) ausente no título curto (< 55).
    def rule_title_model
      return [] unless title_editable?

      model = @item&.model.to_s.strip
      return [] if model.length <= 2
      return [] if title.length >= 55
      return [] if normalize(title).include?(normalize(model))

      [ suggestion(3, "título", "Incluir modelo no título", "O modelo \"#{model}\" não aparece no título.", action: title_action) ]
    end

    # 14 — Título com termos proibidos pela política do ML.
    def rule_policy_terms
      return [] unless title_editable?

      normalized = normalize(title)
      matched = BANNED_TERMS.select { |term| normalized.include?(term) }
      return [] if matched.empty?

      [ suggestion(1, "política", "Remover termos não permitidos do título", "Termos que violam a política do Mercado Livre: #{matched.join(', ')}.",
                   action: title_action) ]
    end

    # 15 — Atributos obrigatórios faltando (detalhes precisam ter carregado).
    def rule_attrs_required
      return [] unless details_loaded?

      missing = Array(@item&.attrs_missing_required)
      return [] if missing.empty?

      [ suggestion(1, "ficha técnica", "Completar atributos obrigatórios", "Atributos obrigatórios faltando: #{missing.join(', ')}.",
                   action: { kind: "alterar_ficha" }) ]
    end

    # 16 — Características principais faltando.
    def rule_attrs_main
      return [] unless details_loaded?

      missing = Array(@item&.attrs_missing_main)
      return [] if missing.empty?

      [ suggestion(2, "ficha técnica", "Completar características principais", "Características principais faltando: #{missing.join(', ')}.",
                   action: { kind: "alterar_ficha" }) ]
    end

    # 17 — Menos de 3 fotos.
    def rule_photos_few
      pictures = @item&.pictures_count.to_i
      return [] unless pictures < 3

      [ suggestion(1, "fotos", "Adicionar fotos", "Apenas #{pictures} foto(s) — o mínimo recomendado é 6 a 10.",
                   action: { kind: "gerar_fotos", suggested_count: [ 6 - pictures, 1 ].max }) ]
    end

    # 18 — 3 a 5 fotos (meta 6-10).
    def rule_photos_low
      pictures = @item&.pictures_count.to_i
      return [] unless pictures.between?(3, 5)

      [ suggestion(2, "fotos", "Adicionar mais fotos", "#{pictures} fotos — a meta é 6 a 10.",
                   action: { kind: "gerar_fotos", suggested_count: [ 6 - pictures, 1 ].max }) ]
    end

    # 19 — Sem vídeo em curva A ou B.
    def rule_video_missing
      return [] if @item&.has_video
      return [] unless %w[A B].include?(@curve)

      [ suggestion(3, "vídeo", "Adicionar vídeo", "Sem vídeo no anúncio — ajuda a converter mais nas curvas A e B.", action: ciente_action) ]
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

      [ suggestion(3, "tipo de anúncio", "Testar anúncio Premium", "Preço alto e o Mercado Livre recomenda parcelamento — o tipo Premium pode ajudar.",
                   action: ciente_action) ]
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

      [ suggestion(3, "frete", "Testar frete grátis", "Preço entre R$ 60 e R$ 79 sem frete grátis — o frete grátis pode aumentar as vendas.",
                   options: free_shipping_options, calculator: price_calculator) ]
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
        suggestion(priority, "qualidade", entry["title"].presence || "Ajustar qualidade do anúncio", entry["label"].presence || entry["title"].to_s,
                   action: ciente_action, key: "qualidade:#{key.presence || entry['title']}")
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

    # key: identifica a sugestão para o "Ciente" (área + título, ou a chave do ML nas de qualidade).
    def suggestion(priority, area, title, why, key: nil, **extra)
      { priority: priority, area: area, title: title, why: why, key: key || "#{area}:#{title}", **extra.compact }
    end

    # Vídeo, Tipo de anúncio e Qualidade: o Lunna não faz por você; "Ciente, aplicada" ou "Ciente, aguardar" (volta em 15 dias).
    def ciente_action = { kind: "ciente" }

    # --- Exposição: medidas concretas, conforme o que o anúncio já tem (pedido do usuário em 04/11/2026) ---
    def exposure_steps
      steps = []
      steps << "Colocar o anúncio no Product Ads (campanha com ROAS objetivo pela margem): é a forma mais rápida de ganhar visitas." unless @in_ads
      steps << "Revisar o título: as palavras que o comprador busca primeiro (produto, marca, modelo, característica principal), até 60 caracteres." if title_editable? && title.length < 55
      steps << "Entrar nas promoções do Mercado Livre que cabem na margem (aba Promoções): o selo de desconto aumenta cliques e posição."
      steps << "Oferecer frete grátis: anúncios com frete grátis ganham destaque na busca." unless @item&.free_shipping || @metric.free_shipping
      steps << "Enviar para o Full: o selo Full e a entrega rápida melhoram a posição na busca." unless full?
      steps << "Completar a ficha técnica: atributos preenchidos fazem o anúncio aparecer nos filtros da busca." if Array(@item&.attrs_missing_main).any? || Array(@item&.attrs_missing_required).any?
      steps << "Melhorar a qualidade do anúncio (#{@item.quality_score}/100): fotos, ficha e descrição completas sobem a posição." if @item&.quality_score.present? && @item.quality_score.to_i < 80
      steps << "Revisar o preço frente aos concorrentes (veja a referência de preço do Mercado Livre)." if @price[:kind] == "suggestion" && @price[:diff_pct].to_f.negative?
      steps
    end

    # --- Preço: opções com a conta da margem (preço − tarifa − frete − imposto − custo) ---
    # Tarifa proporcional ao preço (a % de hoje); frete por unidade igual ao de hoje; imposto pela % da empresa.
    # Sem custo cadastrado: só a referência do ML, com o lucro ANTES do custo (cost: nil).
    def price_options
      return [] unless @unit && @metric.price.to_f.positive?

      fee_pct = @unit[:fee].to_f / @metric.price.to_f
      options = []
      options << price_option("Referência do Mercado Livre", @price[:suggested].to_f, fee_pct) if @price[:suggested].to_f.positive?
      options << price_option("Preço de hoje", @metric.price.to_f, fee_pct, today: true) if options.any?
      return options unless @unit[:cost]

      [ @params.min_margin_pct, @params.min_margin_pct + 5 ].each do |target|
        p = price_for_margin(target, fee_pct)
        options << price_option("Preço para margem de #{target.round(1)}%", p, fee_pct) if p
      end
      options.uniq { |o| o[:price] }.sort_by { |o| o[:price] }
    end

    # O frete muda com o preço: a partir de R$ 79 o frete grátis é obrigatório e o custo do vendedor segue a tabela do ML
    # por faixa (ml_items.ship_cost_tiers; pedido do usuário em 07/11/2026). Abaixo de R$ 79, o frete de hoje.
    FREE_SHIPPING_MIN = 79.0
    SHIP_BANDS = %w[200 150 120 100 79].freeze

    def ship_tiers = @item.respond_to?(:ship_cost_tiers) ? (@item&.ship_cost_tiers || {}) : {}

    def shipping_at(price)
      below = @unit[:shipping].to_f
      return below if price < FREE_SHIPPING_MIN

      band = SHIP_BANDS.find { |b| price >= b.to_f && ship_tiers[b] }
      band ? ship_tiers[band].to_f : (@item&.ship_cost_free.presence || below).to_f
    end

    def price_for_margin(margin_pct, fee_pct)
      divisor = 1 - fee_pct - @params.tax_pct / 100.0 - margin_pct / 100.0
      return nil unless divisor.positive?

      shipping = @unit[:shipping].to_f
      price = nil
      4.times do # o frete depende da faixa do preço: refaz até estabilizar
        price = ((shipping + @unit[:cost].to_f) / divisor).ceil(2)
        next_shipping = shipping_at(price)
        break if (next_shipping - shipping).abs < 0.005

        shipping = next_shipping
      end
      price
    end

    def price_option(label, price, fee_pct, today: false)
      fee = price * fee_pct
      tax = price * @params.tax_pct / 100.0
      shipping = today ? @unit[:shipping].to_f : shipping_at(price)
      cost = @unit[:cost]
      profit = price - fee - shipping - tax - cost.to_f
      label = "#{label} (frete grátis obrigatório a partir de R$ 79)" if !today && price >= FREE_SHIPPING_MIN && @metric.price.to_f < FREE_SHIPPING_MIN
      { label: label, price: price.round(2), fee: fee.round(2), shipping: shipping.round(2), tax: tax.round(2), cost: cost&.round(2),
        profit: profit.round(2), margin_pct: (profit / price * 100).round(1), low: cost ? profit / price * 100 < @params.min_margin_pct : false,
        today: today }
    end

    # Para o campo de preço livre na tela: a mesma conta das opções (tarifa na % de hoje, imposto, custo, frete por faixa).
    def price_calculator
      return nil unless @unit && @metric.price.to_f.positive?

      { current_price: @metric.price.to_f, fee_pct: (@unit[:fee].to_f / @metric.price.to_f).round(6), tax_pct: @params.tax_pct,
        cost: @unit[:cost]&.round(2), ship_below: @unit[:shipping].to_f.round(2), ship_free_below: @item&.ship_cost_free&.to_f,
        ship_tiers: ship_tiers.transform_values(&:to_f), free_shipping_min: FREE_SHIPPING_MIN, min_margin_pct: @params.min_margin_pct }
    end

    # --- Frete grátis: como ficam custos e margem pagando o frete (ml_items.ship_cost_free) ---
    def free_shipping_options
      free = @item&.ship_cost_free
      return [] unless @unit && free.present?

      price = @metric.price.to_f
      today = { label: "Hoje (comprador paga o frete)", price: price, fee: @unit[:fee].to_f.round(2), shipping: @unit[:shipping].to_f.round(2),
                tax: @unit[:tax].to_f.round(2), cost: @unit[:cost]&.round(2), today: true }
      with_free = today.merge(label: "Com frete grátis (você paga R$ #{format('%.2f', free.to_f).tr('.', ',')})", shipping: free.to_f.round(2),
                              today: false, same_price: true)
      opts = [ today, with_free ].map do |o|
        profit = o[:price] - o[:fee] - o[:shipping] - o[:tax] - o[:cost].to_f
        o.merge(profit: profit.round(2), margin_pct: (profit / o[:price] * 100).round(1), low: o[:cost] ? profit / o[:price] * 100 < @params.min_margin_pct : false)
      end
      if @unit[:cost]
        p, cost = keep_margin_with_tiers(free.to_f)
        if p
          label = "Frete grátis mantendo a margem de hoje"
          label += p >= 79 ? " (a partir de R$ 79 o frete grátis é obrigatório; frete de R$ #{format('%.2f', cost).tr('.', ',')} nessa faixa)" : ""
          opts << price_option(label, p, @unit[:fee].to_f / price).merge(shipping: cost.round(2), label: label).then { |o| recalc(o) }
        end
      end
      opts
    end

    # O frete grátis custa conforme a faixa de preço (o ML cobra mais a partir de R$ 100, 120...): o preço que mantém a
    # margem é recalculado com o frete da faixa em que ele cai (ml_items.ship_cost_tiers, lidos do ML).
    def ship_cost_at(price, below)
      return below if price < FREE_SHIPPING_MIN

      band = SHIP_BANDS.find { |b| price >= b.to_f && ship_tiers[b] }
      band ? ship_tiers[band].to_f : below
    end

    def keep_margin_with_tiers(free)
      cost = free
      p = nil
      3.times do
        p = keep_margin_price(cost)
        return [ nil, cost ] unless p

        next_cost = ship_cost_at(p, free)
        break if (next_cost - cost).abs < 0.005

        cost = next_cost
      end
      [ p, cost ]
    end

    def keep_margin_price(free)
      price = @metric.price.to_f
      margin = @unit[:margin_pct].to_f / 100.0
      divisor = 1 - @unit[:fee].to_f / price - @params.tax_pct / 100.0 - margin
      divisor.positive? ? ((free + @unit[:cost].to_f) / divisor).ceil(2) : nil
    end

    def recalc(o)
      profit = o[:price] - o[:fee] - o[:shipping] - o[:tax] - o[:cost].to_f
      o.merge(profit: profit.round(2), margin_pct: (profit / o[:price] * 100).round(1), low: profit / o[:price] * 100 < @params.min_margin_pct)
    end
  end
end
