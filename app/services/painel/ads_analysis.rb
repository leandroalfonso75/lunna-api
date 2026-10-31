# Análise e fila de decisões de Product Ads (seção Ads → aba Análise), com as regras do plugin "Agente ads ml"
# adaptadas ao Lunna (ver docs/secoes/ads.md, "Análise"). Só recomenda: nunca altera campanha.
#
# Unidade de decisão: a FAMÍLIA (produto do ML, `ml_ad_items.family_id`), não o anúncio.
# Janela: os últimos 7 dias fechados (o dia corrente só consolida às 10:00) e os 7 anteriores para comparar; 30 dias
# fechados para as regras de maturação. Métricas dos anúncios vêm de `ml_ad_item_dailies`; orgânico, de
# `ml_ad_daily_metrics`; leilão, de `ml_ad_campaigns.auction`.
#
# Contas:
#   ROAS = receita por Ads ÷ investimento; ACOS = investimento ÷ receita por Ads; TACOS = investimento ÷ (receita por
#   Ads + receita orgânica); ROAS de Equilíbrio = 1 ÷ margem bruta (preço − custo − tarifa − frete − imposto − despesas),
#   com o custo real do Lunna (Olist ou manual). Sem custo, não se afirma lucro.
#
# Regras da casa (declaradas na tela): 30 cliques para julgar conversão, 500 impressões para julgar CTR; gasto relevante
# a partir de R$ 10 no período; anúncio com menos de 30 dias não é julgado; TACOS alvo 3% a 4%; fila de até 7 ações,
# ordenada por dinheiro em jogo; item sem valor estimável vai para "observar".
module Painel
  class AdsAnalysis
    DAYS = 7
    MATURITY_DAYS = 30
    MIN_CLICKS = 30
    MIN_PRINTS = 500
    RELEVANT_COST = 10.0
    MAX_ACTIONS = 7
    TACOS_TARGET = [ 3.0, 4.0 ].freeze
    TACOS_BAD = 6.0
    REFERENCE_EQUILIBRIUM = 3.33 # margem bruta de 30%, referência das fontes quando não há custo
    OFF_AIR = %w[hold delegated revoked].freeze

    CLASSES = {
      "destravar" => "Destravar receita parada", "desperdicio" => "Estancar desperdício",
      "alocacao" => "Corrigir alocação na família", "orcamento" => "Abrir verba onde há retorno",
      "posicao" => "Ganhar posição", "ajuste" => "Ajuste fino"
    }.freeze
    CLASS_ORDER = CLASSES.keys.freeze

    def self.call(account, max_actions: MAX_ACTIONS) = new(account, max_actions: max_actions).call

    def initialize(account, max_actions: MAX_ACTIONS)
      @account = account
      @company = account.company
      @max_actions = max_actions.to_i.clamp(1, 20)
      @zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
      @last = @zone.today - 1
      @from = @last - (DAYS - 1)
      @prev_from = @from - DAYS
      @prev_to = @from - 1
      @month_from = @last - (MATURITY_DAYS - 1)
    end

    def call
      items = @account.ml_ad_items.to_a
      campaigns = @account.ml_ad_campaigns.index_by(&:campaign_id)
      days = item_days(items.map(&:item_id))
      @account_ctr = ctr_of(sum_metrics(days[:now].values.flatten))
      economics = economics_for(items)

      families = build_families(items, days, campaigns, economics)
      campaign_rows = build_campaigns(campaigns, families)
      attach_auction_signals(families, campaign_rows)
      queue, next_round, watch = build_queue(families, campaign_rows)
      health = health_block(days)

      {
        period: { from: @from.iso8601, to: @last.iso8601, days: DAYS, prev_from: @prev_from.iso8601, prev_to: @prev_to.iso8601 },
        rules: { min_clicks: MIN_CLICKS, min_prints: MIN_PRINTS, relevant_cost: RELEVANT_COST, maturity_days: MATURITY_DAYS,
                 max_actions: @max_actions, tacos_target: TACOS_TARGET, tacos_bad: TACOS_BAD, reference_equilibrium: REFERENCE_EQUILIBRIUM,
                 note: "30 cliques para julgar conversão e 500 impressões para julgar CTR são regra da casa, não das fontes." },
        health: health,
        campaigns: campaign_rows,
        families: families.map { |f| f.except(:_items) },
        queue: queue, next_round: next_round, watch: watch,
        untouchables: families.filter_map { |f| f[:untouchable] && { key: f[:key], name: f[:name], reason: f[:untouchable][:reason], until: f[:untouchable][:until] } },
        closing: closing(health, queue),
        generated_at: Time.current
      }
    end

    private

    # --- dados ---

    # => { now: { item_id => [linhas] }, prev: {...}, month: {...} }
    def item_days(item_ids)
      rows = MlAdItemDaily.where(ml_account_id: @account.id, item_id: item_ids, date: @prev_from..@last).to_a
      {
        now: rows.select { |r| r.date >= @from }.group_by(&:item_id),
        prev: rows.select { |r| r.date < @from }.group_by(&:item_id),
        month: MlAdItemDaily.where(ml_account_id: @account.id, item_id: item_ids, date: @month_from..@last).to_a.group_by(&:item_id)
      }
    end

    def sum_metrics(rows)
      m = { cost: 0.0, revenue: 0.0, clicks: 0, prints: 0, units: 0 }
      rows.each do |r|
        m[:cost] += r.cost.to_f
        m[:revenue] += r.total_amount.to_f
        m[:clicks] += r.clicks.to_i
        m[:prints] += r.prints.to_i
        m[:units] += r.units.to_i
      end
      m.merge(derived(m))
    end

    def derived(m)
      {
        roas: m[:cost].positive? ? (m[:revenue] / m[:cost]).round(2) : nil,
        acos: m[:revenue].positive? ? (m[:cost] / m[:revenue] * 100).round(2) : nil,
        ctr: m[:prints].positive? ? (m[:clicks].to_f / m[:prints] * 100).round(3) : nil,
        cvr: m[:clicks].positive? ? (m[:units].to_f / m[:clicks] * 100).round(2) : nil,
        cpc: m[:clicks].positive? ? (m[:cost] / m[:clicks]).round(2) : nil
      }
    end

    def ctr_of(m) = m[:prints] >= MIN_PRINTS ? m[:ctr] : nil

    # Margem bruta e ROAS de Equilíbrio por anúncio, com o custo real do Lunna (Painel::ItemEconomics).
    def economics_for(items)
      metrics = ItemMetric.where(ml_account_id: @account.id, item_id: items.map(&:item_id)).to_a
      ItemEconomics.for_page(@account, metrics)
    end

    def equilibrium_of(eco)
      return nil if eco.nil? || eco[:net_profit_pct].nil?

      margin = eco[:net_profit_pct].to_f
      { price: eco[:price].round(2), cost: eco[:cost]&.round(2), margin_pct: margin.round(2),
        roas_equilibrio: margin.positive? ? (100.0 / margin).round(2) : nil,
        complete: eco[:fees_known] == true, alert: margin.positive? ? nil : "margem não positiva com os custos atuais: rever custo ou preço" }
    end

    # --- famílias ---

    def build_families(items, days, campaigns, economics)
      items.group_by { |i| i.family_id.presence || "item:#{i.item_id}" }.map do |key, group|
        rows = group.map { |i| item_row(i, days, campaigns) }
        active = rows.select { |r| r[:status] == "active" }
        m = sum_metrics(group.flat_map { |i| days[:now][i.item_id] || [] })
        prev = sum_metrics(group.flat_map { |i| days[:prev][i.item_id] || [] })
        month = sum_metrics(group.flat_map { |i| days[:month][i.item_id] || [] })
        lead = (active.presence || rows).max_by { |r| r[:cost] }
        eco = equilibrium_of(economics[lead[:item_id]])
        family = {
          key: key, family_id: group.first.family_id, name: group.first.family_name.presence || lead[:title],
          domain: group.first.domain_id, thumbnail: lead[:thumbnail],
          n_items: rows.size, n_active: active.size, campaigns: group.map(&:campaign_id).compact.uniq,
          metrics: m, previous: prev, month: month,
          variation: { cost: pct_change(m[:cost], prev[:cost]), revenue: pct_change(m[:revenue], prev[:revenue]), roas: pct_change(m[:roas], prev[:roas]) },
          economics: eco,
          sample: { cvr_ok: m[:clicks] >= MIN_CLICKS, ctr_ok: m[:prints] >= MIN_PRINTS },
          items: rows.sort_by { |r| -r[:cost] },
          signals: [],
          _items: group
        }
        family[:untouchable] = untouchable_reason(family, rows)
        family[:signals] = family_signals(family, rows, active) unless family[:untouchable]
        family
      end.sort_by { |f| -f[:metrics][:cost] }
    end

    def item_row(item, days, campaigns)
      m = sum_metrics(days[:now][item.item_id] || [])
      campaign = campaigns[item.campaign_id]
      age = item.date_created ? (@zone.today - item.date_created.in_time_zone(@zone).to_date).to_i : nil
      {
        item_id: item.item_id, title: item.title, status: item.status, campaign_id: item.campaign_id, campaign: campaign&.name,
        thumbnail: item.thumbnail, permalink: item.permalink, price: item.price&.to_f, image_quality: item.image_quality,
        catalog: item.catalog_listing, buy_box_winner: item.buy_box_winner, recommended: item.recommended,
        date_created: item.date_created, age_days: age, **m
      }
    end

    def pct_change(now, before)
      return nil if now.nil? || before.nil? || before.to_f.zero?

      ((now.to_f - before.to_f) / before.to_f.abs * 100).round(1)
    end

    # Em maturação (todos os anúncios com menos de 30 dias) ou amostra insuficiente: não se julga.
    def untouchable_reason(family, rows)
      ages = rows.filter_map { |r| r[:age_days] }
      if ages.any? && ages.all? { |a| a < MATURITY_DAYS }
        newest = rows.filter_map { |r| r[:date_created] }.max
        return { reason: "em maturação (anúncio com #{ages.min} dias; só se julga com 30)", until: (newest.in_time_zone(@zone).to_date + MATURITY_DAYS).iso8601 }
      end
      m = family[:metrics]
      if m[:cost].positive? && m[:clicks] < MIN_CLICKS && m[:prints] < MIN_PRINTS
        return { reason: "amostra insuficiente (#{m[:clicks]} cliques, #{m[:prints]} impressões)", until: nil }
      end

      nil
    end

    def family_signals(family, rows, active)
      m = family[:metrics]
      signals = []
      off = rows.select { |r| OFF_AIR.include?(r[:status]) && r[:revenue].positive? }
      if off.any?
        lost = off.sum { |r| r[:revenue] }.round(2)
        signals << { type: "saiu_do_ar_com_historico", priority: "alta", value: lost, item_ids: off.map { |r| r[:item_id] },
                     detail: "#{off.size} anúncio(s) fora do ar hoje (#{off.map { |r| r[:status] }.uniq.join(', ')}) geraram #{brl(lost)} por Ads no período. Quase sempre é item pausado ou sem estoque: conferir antes de qualquer lance." }
      end
      if m[:cost] >= RELEVANT_COST && m[:revenue].zero?
        signals << { type: "gasto_sem_receita", priority: "alta", value: m[:cost].round(2),
                     detail: "#{brl(m[:cost])} investidos e nenhuma venda por Ads no período (relevância: #{brl(RELEVANT_COST)})." }
      end
      if m[:prints] >= MIN_PRINTS && m[:clicks].zero?
        signals << { type: "impressao_sem_clique", priority: "media", value: nil,
                     detail: "#{m[:prints]} impressões e nenhum clique: amostra suficiente para julgar capa e título." }
      end
      eq = family.dig(:economics, :roas_equilibrio)
      # sem receita, "gasto sem receita" já cobre (não duplicar o item na fila)
      if m[:roas] && eq && m[:roas] < eq && m[:revenue].positive?
        waste = [ m[:cost] - m[:revenue] / eq, 0 ].max.round(2)
        signals << { type: "abaixo_do_equilibrio", priority: "alta", value: waste,
                     detail: "ROAS #{m[:roas]} abaixo do equilíbrio #{eq} (margem bruta #{family[:economics][:margin_pct]}%)#{family[:economics][:complete] ? '' : ' — equilíbrio parcial: sem a tarifa detalhada, o real é maior'}." }
      end
      if active.size > 1 && active.count { |r| r[:cost].positive? } > 1
        best, *rest = active.select { |r| r[:roas] }.sort_by { |r| -r[:roas] }
        worst = rest.last
        if best && worst && worst[:cost] > best[:cost]
          gain = (worst[:cost] * (best[:roas] - worst[:roas])).round(2)
          signals << { type: "familia_com_multiplos_anuncios_ativos", priority: "media", value: gain, best: best[:item_id], worst: worst[:item_id],
                       detail: "#{active.size} anúncios ativos do mesmo produto; a verba maior (#{brl(worst[:cost])}) está no de pior ROAS (#{worst[:roas]}) e o melhor (ROAS #{best[:roas]}) recebe #{brl(best[:cost])}." }
        end
      end
      qualities = active.map { |r| r[:image_quality] }.compact
      if qualities.any? && qualities.none? { |q| q == "good_quality_thumbnail" } && @account_ctr && m[:prints] >= MIN_PRINTS && m[:ctr].to_f < @account_ctr
        signals << { type: "capa_suspeita", priority: "media", value: nil,
                     detail: "CTR #{m[:ctr]}% abaixo da média da conta (#{@account_ctr}%) com #{m[:prints]} impressões e nenhum anúncio com selo de imagem (#{qualities.uniq.join(', ')}). Trocar a capa antes de mexer em lance." }
      end
      idle = rows.select { |r| r[:status] == "idle" && r[:recommended] }
      if idle.any?
        signals << { type: "idle_recomendado", priority: "baixa", value: nil, item_ids: idle.map { |r| r[:item_id] },
                     detail: "#{idle.size} anúncio(s) fora de campanha que o ML marca como recomendado para anunciar." }
      end
      signals
    end

    # --- campanhas e leilão ---

    def build_campaigns(campaigns, families)
      by_campaign = Hash.new { |h, k| h[k] = [] }
      families.each { |f| f[:campaigns].each { |cid| by_campaign[cid] << f } }
      campaigns.values.map do |c|
        fams = by_campaign[c.campaign_id]
        active_fams = fams.select { |f| f[:_items].any? { |i| i.campaign_id == c.campaign_id && i.status == "active" } }
        m = sum_metrics(fams.flat_map { |f| f[:_items].select { |i| i.campaign_id == c.campaign_id } }.flat_map { |i| days_cache(i.item_id) })
        a = c.auction["7d"] || {}
        prev = c.auction["7d_prev"] || {}
        eq = active_fams.filter_map { |f| f.dig(:economics, :roas_equilibrio) }.max
        {
          id: c.campaign_id, name: c.name, status: c.status, strategy: c.strategy, roas_target: c.roas_target&.to_f,
          acos_target: c.acos_target&.to_f, budget: c.budget&.to_f, daily_budget: c.daily_budget&.to_f,
          families: active_fams.size, attribution: active_fams.size == 1 ? "exata" : "compartilhada",
          metrics: m, equilibrium: eq,
          auction: { impression_share: a["impression_share"], top_impression_share: a["top_impression_share"],
                     lost_by_budget: a["lost_by_budget"], lost_by_ad_rank: a["lost_by_ad_rank"], acos_benchmark: a["acos_benchmark"],
                     consistent: a["consistent"], prev_impression_share: prev["impression_share"], synced_at: c.auction_synced_at },
          acos_vs_benchmark: m[:acos] && a["acos_benchmark"].to_f.positive? ? (m[:acos] - a["acos_benchmark"].to_f).round(2) : nil
        }
      end.sort_by { |c| [ c[:status] == "active" ? 0 : 1, -c[:metrics][:cost] ] }
    end

    def days_cache(item_id)
      @days_cache ||= MlAdItemDaily.where(ml_account_id: @account.id, date: @from..@last).to_a.group_by(&:item_id)
      @days_cache[item_id] || []
    end

    # Exposição por família só quando a campanha tem uma família ativa (share exato); senão fica no nível da campanha.
    def attach_auction_signals(families, campaign_rows)
      exact = campaign_rows.select { |c| c[:attribution] == "exata" && c[:status] == "active" }.index_by { |c| c[:id] }
      families.each do |f|
        next if f[:untouchable] || f[:metrics][:cost] < RELEVANT_COST

        c = f[:campaigns].filter_map { |cid| exact[cid] }.first
        next unless c && c[:auction][:consistent]

        a = c[:auction]
        if a[:lost_by_budget].to_f >= 0.20
          f[:signals] << { type: "exposicao_perdida_por_orcamento", priority: "alta", value: budget_value(f[:metrics], a), campaign_id: c[:id],
                           detail: "perde #{pct(a[:lost_by_budget])} das impressões por orçamento na campanha #{c[:name]}, com ROAS #{f[:metrics][:roas] || '—'}. Aumentar verba é a ação certa; conferir estoque antes." }
        end
        if a[:lost_by_ad_rank].to_f >= 0.50
          f[:signals] << { type: "exposicao_perdida_por_ad_rank", priority: "media", value: nil, campaign_id: c[:id],
                           detail: "aparece em #{pct(a[:impression_share])} das oportunidades; perde #{pct(a[:lost_by_ad_rank])} por classificação. A alavanca é qualidade do anúncio ou ROAS Objetivo mais baixo; verba não compra posição." }
        end
      end
    end

    def budget_value(m, a)
      share = a[:impression_share].to_f
      return nil unless share.positive? && m[:revenue].positive?

      (m[:revenue] * a[:lost_by_budget].to_f / share).round(2)
    end

    # --- fila de decisões ---

    def build_queue(families, campaign_rows)
      items = []
      families.each do |f|
        f[:signals].each do |s|
          entry = queue_entry(f, s)
          items << entry if entry
        end
      end
      campaign_rows.each do |c|
        next unless c[:status] == "active" && c[:attribution] == "compartilhada" && c[:auction][:consistent] && c[:metrics][:cost] >= RELEVANT_COST

        items << campaign_budget_entry(c) if c[:auction][:lost_by_budget].to_f >= 0.20
        items << campaign_rank_entry(c) if c[:auction][:lost_by_ad_rank].to_f >= 0.50
      end
      items = items.compact
      numbered, watch = items.partition { |i| i[:value].to_f.positive? }
      numbered = numbered.sort_by { |i| [ CLASS_ORDER.index(i[:class]), -i[:value] ] }
      queue = numbered.first(@max_actions).each_with_index.map { |i, idx| i.merge(n: idx + 1) }
      [ queue, numbered.drop(@max_actions), watch ]
    end

    def queue_entry(f, s)
      name = f[:name]
      base = { key: f[:key], family_name: name, signal: s[:type], value: s[:value], evidence: s[:detail], reassess: "7 dias" }
      case s[:type]
      when "saiu_do_ar_com_historico"
        base.merge(class: "destravar", class_label: CLASSES["destravar"], title: name, value_how: "receita por Ads do período dos anúncios fora do ar",
                   action: "Conferir no Mercado Livre o(s) anúncio(s) #{s[:item_ids].join(', ')}: reativar ou repor estoque.",
                   check_before: "estoque no Olist/Full e situação do anúncio no ML")
      when "gasto_sem_receita"
        base.merge(class: "desperdicio", class_label: CLASSES["desperdicio"], title: name, value_how: "investimento sem retorno no período",
                   action: "Comparar preço, frete e fotos com o líder da categoria; se seguir sem venda por 30 dias, pausar a publicidade do(s) anúncio(s) #{f[:items].select { |r| r[:cost].positive? }.map { |r| r[:item_id] }.join(', ')}.",
                   check_before: "preço e frete contra o 'Mais vendido'; ficha técnica completa", reassess: "30 dias (maturação)")
      when "abaixo_do_equilibrio"
        base.merge(class: "desperdicio", class_label: CLASSES["desperdicio"], title: name, value_how: "parte do investimento acima do que a receita sustenta no equilíbrio",
                   action: "ROAS #{f[:metrics][:roas]} abaixo do equilíbrio #{f[:economics][:roas_equilibrio]}: rever preço e custo (margem #{f[:economics][:margin_pct]}%); se não houver como subir a margem, pausar a publicidade desta família.",
                   check_before: "custo do produto e preço no Lunna; não baixar lance como primeira ação")
      when "familia_com_multiplos_anuncios_ativos"
        base.merge(class: "alocacao", class_label: CLASSES["alocacao"], title: name, value_how: "verba do anúncio pior × diferença de ROAS",
                   action: "Concentrar a verba no anúncio #{s[:best]} (melhor ROAS) e pausar a publicidade do #{s[:worst]}; não excluir o anúncio (perde reviews e relevância).",
                   check_before: "estoque dos dois; preço igual entre eles")
      when "exposicao_perdida_por_orcamento"
        base.merge(class: "orcamento", class_label: CLASSES["orcamento"], title: name, value_how: "receita do período × impressões perdidas por orçamento ÷ impressões obtidas (estimativa)",
                   action: "Aumentar o orçamento diário da campanha #{f[:items].first[:campaign]}; não mexer no ROAS Objetivo.",
                   check_before: "estoque (cobertura) e reputação da conta")
      when "exposicao_perdida_por_ad_rank"
        base.merge(class: "posicao", class_label: CLASSES["posicao"], title: name, value_how: nil,
                   action: "Melhorar capa, ficha técnica e preço, ou baixar o ROAS Objetivo da campanha; aumentar orçamento não resolve.",
                   check_before: "qualidade do anúncio (capa, ficha, reputação)")
      when "capa_suspeita", "impressao_sem_clique"
        base.merge(class: "ajuste", class_label: CLASSES["ajuste"], title: name, value_how: nil,
                   action: "Trocar a imagem principal (1200×1200, fundo branco) e revisar o título com os termos reais de busca; nada de lance.",
                   check_before: "padrão de imagem do ML")
      when "idle_recomendado"
        base.merge(class: "ajuste", class_label: CLASSES["ajuste"], title: name, value_how: nil,
                   action: "Avaliar incluir em campanha os anúncios #{s[:item_ids].first(3).join(', ')} (o ML os marca como recomendados).",
                   check_before: "estoque e margem do produto")
      end
    end

    def campaign_budget_entry(c)
      a = c[:auction]
      value = budget_value(c[:metrics], a)
      ok = c[:equilibrium] ? c[:metrics][:roas].to_f >= c[:equilibrium] : c[:metrics][:roas].to_f >= REFERENCE_EQUILIBRIUM
      return nil unless ok

      { key: "campaign:#{c[:id]}", campaign_id: c[:id], class: "orcamento", class_label: CLASSES["orcamento"], title: "Campanha #{c[:name]}",
        signal: "exposicao_perdida_por_orcamento", value: value, value_how: "receita do período × impressões perdidas por orçamento ÷ impressões obtidas (estimativa; campanha com #{c[:families]} famílias)",
        evidence: "perde #{pct(a[:lost_by_budget])} das impressões por orçamento; aparece em #{pct(a[:impression_share])}; ROAS #{c[:metrics][:roas]} #{c[:equilibrium] ? "acima do equilíbrio #{c[:equilibrium]}" : "acima da referência #{REFERENCE_EQUILIBRIUM} (sem custo nas famílias)"}; orçamento diário #{brl(c[:daily_budget])}.",
        action: "Aumentar o orçamento diário da campanha #{c[:name]} de #{brl(c[:daily_budget])} para #{brl((c[:daily_budget].to_f * 1.3).round(0))} (+30%) e reavaliar; não mexer no ROAS Objetivo.",
        check_before: "estoque das famílias da campanha e reputação da conta", reassess: "7 dias" }
    end

    def campaign_rank_entry(c)
      a = c[:auction]
      share = a[:impression_share].to_f
      value = share.positive? && c[:metrics][:revenue].positive? ? [ c[:metrics][:revenue] * a[:lost_by_ad_rank].to_f / share, c[:metrics][:revenue] ].min.round(2) : nil
      { key: "campaign:#{c[:id]}", campaign_id: c[:id], class: "posicao", class_label: CLASSES["posicao"], title: "Campanha #{c[:name]}",
        signal: "exposicao_perdida_por_ad_rank", value: value, value_how: "receita do período × parcela perdida por classificação (estimativa, teto: dobrar a receita)",
        evidence: "aparece em #{pct(share)} das oportunidades; perde #{pct(a[:lost_by_ad_rank])} por classificação e #{pct(a[:lost_by_budget])} por orçamento; ACOS #{c[:metrics][:acos] || '—'}% contra benchmark #{a[:acos_benchmark]}%; ROAS Objetivo #{c[:roas_target] || '—'}.",
        action: "Baixar o ROAS Objetivo da campanha #{c[:name]}#{c[:roas_target] ? " de #{c[:roas_target]} para #{(c[:roas_target] * 0.8).round(1)}" : ''} para o lance subir, e melhorar capa/ficha dos anúncios de maior gasto; aumentar orçamento não compra posição.",
        check_before: "margem das famílias (ROAS Objetivo não pode ficar abaixo do equilíbrio)", reassess: "7 dias" }
    end

    # --- saúde da conta ---

    def health_block(days)
      now = sum_metrics(days[:now].values.flatten)
      prev = sum_metrics(days[:prev].values.flatten)
      organic_now = organic_between(@from, @last)
      organic_prev = organic_between(@prev_from, @prev_to)
      block = ->(m, organic) do
        total = m[:revenue] + organic
        m.merge(organic: organic.round(2), total_revenue: total.round(2),
                tacos: total.positive? ? (m[:cost] / total * 100).round(2) : nil,
                ads_share: total.positive? ? (m[:revenue] / total * 100).round(1) : nil)
      end
      h = block.(now, organic_now)
      p = block.(prev, organic_prev)
      h.merge(previous: p, tacos_state: tacos_state(h[:tacos]),
              variation: { cost: pct_change(h[:cost], p[:cost]), revenue: pct_change(h[:revenue], p[:revenue]), roas: pct_change(h[:roas], p[:roas]),
                           tacos: h[:tacos] && p[:tacos] ? (h[:tacos] - p[:tacos]).round(2) : nil, organic: pct_change(h[:organic], p[:organic]) })
    end

    def organic_between(from, to)
      @account.ml_ad_daily_metrics.where(date: from..to).sum(:organic_amount).to_f
    end

    def tacos_state(tacos)
      return "sem_dados" if tacos.nil?
      return "ok" if tacos <= TACOS_TARGET.last
      return "bad" if tacos > TACOS_BAD

      "warn"
    end

    def closing(health, queue)
      waste = queue.count { |i| %w[desperdicio alocacao].include?(i[:class]) }
      spend = queue.count { |i| i[:class] == "orcamento" }
      direction = if waste > spend then "cair"
      elsif spend > waste then "subir (com mais receita junto)"
      else "ficar parecido"
      end
      { tacos: health[:tacos], previous_tacos: health.dig(:previous, :tacos), target: TACOS_TARGET, direction: direction,
        text: "TACOS de #{health[:tacos] || '—'}% (antes #{health.dig(:previous, :tacos) || '—'}%; alvo #{TACOS_TARGET.join(' a ')}%). Executando a fila, tende a #{direction}." }
    end

    def brl(v) = ActiveSupport::NumberHelper.number_to_currency(v.to_f, unit: "R$ ", separator: ",", delimiter: ".")
    def pct(v) = "#{(v.to_f * 100).round}%"
  end
end
