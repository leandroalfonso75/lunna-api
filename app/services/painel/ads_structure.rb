# Sugestões de ESTRUTURA de campanhas de Product Ads (aba Análise → "Estrutura de campanhas"), só recomendação:
#   - dividir: família que concentra verba numa campanha compartilhada e rende acima do equilíbrio → campanha exclusiva
#     (share de impressões exato, orçamento e ROAS Objetivo próprios), levando a verba junto (sem dinheiro novo);
#   - mover: família abaixo do equilíbrio numa campanha de crescimento → campanha de rentabilidade (ROAS Objetivo alto);
#   - ativar: anúncio fora de campanha (idle) que vende sozinho ou que o ML recomenda, com margem e estoque → entrar
#     numa campanha compatível ou exclusiva, com orçamento dimensionado pelo TACOS alvo;
#   - reativar: anúncio pausado na publicidade que rendia acima do equilíbrio nos 90 dias;
#   - reduzir: campanha abaixo do equilíbrio cedendo verba quando o plano passa do limite diário.
# Tudo respeita o limite máximo de investimento diário (`companies.ads_daily_budget_max`): o que não cabe fica marcado
# "só com realocação". Estimativas declaradas como tal (ver docs/secoes/ads.md).
module Painel
  class AdsStructure
    TACOS_MID = 3.5 # meio da faixa alvo (3% a 4%)
    UPLIFT_PCT = 27.0 # aumento de vendas ao ativar Ads citado pela plataforma (26% a 28%)
    MIN_SHARE = 0.25
    MIN_FAMILIES = 3
    MIN_ORGANIC_UNITS = 3

    def self.call(account, analysis) = new(account, analysis).call

    def initialize(account, analysis)
      @account = account
      @company = account.company
      @analysis = analysis
      @families = analysis[:families]
      @campaigns = analysis[:campaigns]
      @max = @company.ads_daily_budget_max&.to_f
    end

    def call
      suggestions = split_suggestions + move_suggestions + activate_suggestions + reactivate_suggestions
      plan = budget_plan(suggestions)
      { daily_max: @max, current_daily: current_daily.round(2), suggestions: suggestions, plan: plan }
    end

    private

    def current_daily = @campaigns.select { |c| c[:status] == "active" }.sum { |c| c[:daily_budget].to_f }

    def active_items = @account.ml_ad_items.to_a

    # --- dividir: família forte em campanha compartilhada ---

    def split_suggestions
      @campaigns.select { |c| c[:status] == "active" && c[:families] >= MIN_FAMILIES && c[:metrics][:cost] >= AdsAnalysis::RELEVANT_COST }.flat_map do |c|
        a = c[:auction]
        next [] unless a[:consistent] && (a[:lost_by_ad_rank].to_f >= 0.5 || a[:lost_by_budget].to_f >= 0.2)

        @families.select { |f| f[:campaigns].include?(c[:id]) && !f[:untouchable] }.filter_map do |f|
          share = c[:metrics][:cost].positive? ? f[:metrics][:cost] / c[:metrics][:cost] : 0
          eq = f.dig(:economics, :roas_equilibrio) || AdsAnalysis::REFERENCE_EQUILIBRIUM
          next unless share >= MIN_SHARE && f[:metrics][:roas].to_f >= eq && f[:sample][:cvr_ok]

          budget = (c[:daily_budget].to_f * share).round
          {
            type: "dividir", title: f[:name], key: f[:key], item_ids: f[:items].select { |i| i[:status] == "active" }.map { |i| i[:item_id] },
            from_campaign: c[:name], to_campaign: "nova: #{f[:name].to_s.truncate(40)} (exclusiva)",
            daily_budget: budget, frees_from: { campaign_id: c[:id], amount: budget }, roas_target: target_for(eq, "crescimento"),
            value: f[:metrics][:revenue].round(2),
            rationale: "Concentra #{(share * 100).round}% da verba da campanha #{c[:name]} (#{c[:families]} famílias) com ROAS #{f[:metrics][:roas]} (equilíbrio #{eq}); a campanha perde #{pct(a[:lost_by_ad_rank])} por classificação e #{pct(a[:lost_by_budget])} por orçamento. Sozinha, ganha share de impressões exato, orçamento e ROAS Objetivo próprios, sem disputar verba com famílias piores.",
            expected: "Mesmo investimento (#{brl(budget)}/dia saem de #{c[:name]}); TACOS da família tende a cair com o lance calibrado pelo equilíbrio dela.",
            check_before: "estoque da família e reputação; criar a campanha e mover os anúncios no Seller Center (o histórico fica no anúncio)"
          }
        end
      end
    end

    # --- mover: família abaixo do equilíbrio em campanha de crescimento ---

    def move_suggestions
      @families.select { |f| !f[:untouchable] && f[:signals].any? { |s| s[:type] == "abaixo_do_equilibrio" } }.filter_map do |f|
        c = @campaigns.find { |x| f[:campaigns].include?(x[:id]) && x[:status] == "active" }
        next unless c && c[:families] >= 2

        eq = f[:economics][:roas_equilibrio]
        next if c[:roas_target].to_f >= eq * 1.5 # a campanha já é de rentabilidade para esta família

        daily = (f[:metrics][:cost] / AdsAnalysis::DAYS).round(2)
        {
          type: "mover", title: f[:name], key: f[:key], item_ids: f[:items].select { |i| i[:status] == "active" }.map { |i| i[:item_id] },
          from_campaign: c[:name], to_campaign: "nova: Rentabilidade (ROAS Objetivo alto)", daily_budget: [ daily.ceil, 5 ].max,
          frees_from: { campaign_id: c[:id], amount: [ daily.ceil, 5 ].max }, roas_target: target_for(eq, "rentabilidade"),
          value: f[:signals].find { |s| s[:type] == "abaixo_do_equilibrio" }[:value],
          rationale: "ROAS #{f[:metrics][:roas]} abaixo do equilíbrio #{eq} dentro de #{c[:name]} (ROAS Objetivo #{c[:roas_target] || '—'}). Numa campanha de rentabilidade, com ROAS Objetivo #{target_for(eq, 'rentabilidade')}, o lance só sobe quando a venda paga a margem.",
          expected: "Corta o investimento que hoje sai no prejuízo; volume menor, lucro por venda positivo.",
          check_before: "custo e preço da família (se a margem subir, nem precisa mover)"
        }
      end
    end

    # --- ativar: fora de campanha com potencial ---

    def activate_suggestions
      idle = active_items.select { |i| i[:status] == "idle" }
      return [] if idle.empty?

      metrics = ItemMetric.where(ml_account_id: @account.id, item_id: idle.map(&:item_id)).index_by(&:item_id)
      economics = ItemEconomics.for_page(@account, metrics.values)
      idle.filter_map do |i|
        m = metrics[i.item_id]
        eco = economics[i.item_id]
        next unless m && eco && eco[:net_profit_pct].to_f.positive? && m.stock.to_i.positive?
        next unless i.recommended || m.units_30d.to_i >= MIN_ORGANIC_UNITS

        daily_rev = m.revenue_30d.to_f / 30
        budget = [ (daily_rev * TACOS_MID / 100).round, 1 ].max
        eq = (100.0 / eco[:net_profit_pct]).round(2)
        target = suggested_campaign(i, eq)
        {
          type: "ativar", title: i.title, key: "item:#{i.item_id}", item_ids: [ i.item_id ], from_campaign: nil,
          to_campaign: target[:name], daily_budget: budget, frees_from: nil, roas_target: target_for(eq, "crescimento"),
          value: (daily_rev * UPLIFT_PCT / 100 * AdsAnalysis::DAYS).round(2),
          rationale: "#{i.recommended ? 'O ML marca como recomendado para anunciar; vende' : 'Vende'} #{m.units_30d} un. em 30 dias sem Ads (#{brl(m.revenue_30d)}), margem bruta #{eco[:net_profit_pct].round(1)}% (equilíbrio #{eq}), #{m.stock} em estoque. Orçamento de #{brl(budget)}/dia mantém o TACOS em ~#{TACOS_MID}% sobre a receita atual.",
          expected: "Potencial de +#{UPLIFT_PCT.round}% nas vendas (média citada pela plataforma; estimativa), ou #{brl((daily_rev * UPLIFT_PCT / 100 * AdsAnalysis::DAYS).round(2))} em 7 dias.",
          check_before: "estoque (cobertura) e reputação; começar com ROAS Objetivo #{target_for(eq, 'crescimento')} e revisar em 7 dias"
        }
      end
    end

    # --- reativar: pausado que rendia ---

    def reactivate_suggestions
      paused = active_items.select { |i| i[:status] == "paused" }
      return [] if paused.empty?

      metrics = ItemMetric.where(ml_account_id: @account.id, item_id: paused.map(&:item_id)).index_by(&:item_id)
      economics = ItemEconomics.for_page(@account, metrics.values)
      paused.filter_map do |i|
        h = i.metrics["90d"] || {}
        cost = h["cost"].to_f
        revenue = h["total_amount"].to_f
        next unless cost.positive? && revenue.positive? && h["units_quantity"].to_i >= 1
        eco = economics[i.item_id]
        eq = eco && eco[:net_profit_pct].to_f.positive? ? (100.0 / eco[:net_profit_pct]).round(2) : AdsAnalysis::REFERENCE_EQUILIBRIUM
        roas = (revenue / cost).round(2)
        next unless roas >= eq && metrics[i.item_id]&.stock.to_i.positive?

        campaign = @campaigns.find { |c| c[:id] == i.campaign_id }
        daily = [ (cost / 90).ceil, 2 ].max
        {
          type: "reativar", title: i.title, key: "item:#{i.item_id}", item_ids: [ i.item_id ], from_campaign: campaign&.dig(:name),
          to_campaign: campaign&.dig(:name) || "campanha atual", daily_budget: daily, frees_from: nil, roas_target: target_for(eq, "crescimento"),
          value: (revenue / 90 * AdsAnalysis::DAYS).round(2),
          rationale: "Pausado na publicidade, mas nos últimos 90 dias rendeu ROAS #{roas} (#{brl(revenue)} com #{brl(cost)}), acima do equilíbrio #{eq}; #{metrics[i.item_id].stock} em estoque.",
          expected: "Retoma ~#{brl((revenue / 90 * AdsAnalysis::DAYS).round(2))} por semana com ~#{brl(daily)}/dia (média dos 90 dias; estimativa).",
          check_before: "motivo da pausa (estoque, preço) antes de reativar"
        }
      end
    end

    # Campanha existente do mesmo tipo de produto que rende acima do equilíbrio; senão, exclusiva.
    def suggested_campaign(item, eq)
      same = active_items.select { |x| x.status == "active" && x.domain_id == item.domain_id && x.campaign_id }.map(&:campaign_id).tally
      best = same.keys.map { |cid| @campaigns.find { |c| c[:id] == cid && c[:status] == "active" } }.compact
        .select { |c| c[:metrics][:roas].to_f >= eq }.max_by { |c| c[:metrics][:roas].to_f }
      best ? { name: best[:name], id: best[:id] } : { name: "nova: #{item.title.to_s.truncate(40)} (exclusiva)", id: nil }
    end

    # ROAS Objetivo sugerido: crescimento = acima do equilíbrio com folga (mínimo 3,3); rentabilidade = bem acima (mínimo 6).
    def target_for(eq, strategy)
      base = strategy == "rentabilidade" ? [ eq * 1.5, 6.0 ].max : [ eq * 1.2, 3.3 ].max
      base.round(1).clamp(1.0, 35.0)
    end

    # --- limite diário ---

    # Soma o que é dinheiro novo (ativar/reativar) sobre o orçamento atual; dividir/mover só realocam. Passou do limite:
    # marca as novas que não cabem e sugere reduzir campanhas abaixo do equilíbrio para liberar verba.
    def budget_plan(suggestions)
      current = current_daily
      new_money = suggestions.select { |s| s[:frees_from].nil? }.sort_by { |s| -s[:value].to_f }
      running = current
      new_money.each do |s|
        if @max && running + s[:daily_budget].to_f > @max
          s[:within_limit] = false
          s[:note] = "não cabe no limite diário de #{brl(@max)}: só com realocação"
        else
          s[:within_limit] = true
          running += s[:daily_budget].to_f
        end
      end
      suggestions.each { |s| s[:within_limit] = true if s[:frees_from] }
      reductions = []
      if @max && new_money.any? { |s| !s[:within_limit] }
        needed = new_money.reject { |s| s[:within_limit] }.sum { |s| s[:daily_budget].to_f }
        @campaigns.select { |c| c[:status] == "active" && c[:equilibrium] && c[:metrics][:roas].to_f < c[:equilibrium] && c[:daily_budget].to_f.positive? }
          .sort_by { |c| c[:metrics][:roas].to_f }.each do |c|
          break if needed <= 0

          half = (c[:daily_budget].to_f * 0.5).round
          # Campanha muito abaixo do equilíbrio (menos da metade) cede metade da verba; as demais, só o necessário.
          cut = c[:metrics][:roas].to_f < c[:equilibrium] / 2.0 ? [ half, needed.ceil ].max : [ half, needed.ceil ].min
          cut = [ cut, c[:daily_budget].to_f.floor ].min
          next if cut <= 0

          reductions << { type: "reduzir", title: "Campanha #{c[:name]}", key: "campaign:#{c[:id]}", item_ids: [], from_campaign: c[:name], to_campaign: nil,
                          daily_budget: -cut, frees_from: nil, roas_target: nil, value: nil, within_limit: true,
                          rationale: "ROAS #{c[:metrics][:roas]} abaixo do equilíbrio #{c[:equilibrium]}: reduzir o orçamento diário de #{brl(c[:daily_budget])} para #{brl(c[:daily_budget].to_f - cut)} libera #{brl(cut)}/dia para os anúncios com potencial.",
                          expected: "Libera verba sem passar do limite.", check_before: "famílias dentro da campanha que ainda rendem" }
          needed -= cut
        end
      end
      suggestions.concat(reductions)
      # Com a verba liberada, o que não cabia passa a caber "com a redução".
      if reductions.any?
        running += reductions.sum { |s| s[:daily_budget].to_f }
        new_money.reject { |s| s[:within_limit] }.each do |s|
          next unless running + s[:daily_budget].to_f <= @max

          s[:within_limit] = true
          s[:note] = "cabe no limite diário só com a redução sugerida em #{reductions.map { |r| r[:from_campaign] }.uniq.join(', ')}"
          running += s[:daily_budget].to_f
        end
      end
      after = current + new_money.select { |s| s[:within_limit] }.sum { |s| s[:daily_budget].to_f } + reductions.sum { |s| s[:daily_budget].to_f }
      { current_daily: current.round(2), new_daily: new_money.select { |s| s[:within_limit] }.sum { |s| s[:daily_budget].to_f }.round(2),
        reallocated_daily: suggestions.select { |s| s[:frees_from] }.sum { |s| s[:daily_budget].to_f }.round(2),
        after_daily: after.round(2), daily_max: @max, fits: @max.nil? || after <= @max + 0.01,
        note: @max.nil? ? "Informe o limite máximo de investimento diário em Configurações → Anúncios para o plano respeitar o teto." : nil }
    end

    def brl(v) = ActiveSupport::NumberHelper.number_to_currency(v.to_f, unit: "R$", separator: ",", delimiter: ".")
    def pct(v) = "#{(v.to_f * 100).round}%"
  end
end
