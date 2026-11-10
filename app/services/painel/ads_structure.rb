# Sugestões de ESTRUTURA de campanhas de Product Ads (aba Análise → "Estrutura de campanhas"), só recomendação, montadas
# como UMA RODADA coerente: cada sugestão é lançada num razão por campanha (orçamento e ROAS Objetivo antes → depois) e
# só entra se não conflitar com o que a rodada já mudou. Regras (decisões do usuário em 03/11/2026):
#   - rodada semanal: o que foi marcado "Feito" nos últimos 7 dias trava a família/anúncio e as campanhas envolvidas
#     (aprendizado do ML e janela do "depois"); nada novo mexe nelas até a próxima rodada;
#   - uma mudança estrutural por campanha por rodada (dividir OU mover); ativar só entra em campanha não travada;
#   - dividir: só com equilíbrio real (custo conhecido), família só nessa campanha, orçamento pelo GASTO real dela e a
#     campanha de origem fica com o que as outras famílias gastam de fato; ROAS Objetivo da nova começa perto do
#     praticado e desce aos poucos até o piso (equilíbrio × 1,35);
#   - ativar em campanha existente não tem ROAS por anúncio (vale o da campanha, que precisa ficar ≥ 1,2 × o equilíbrio
#     do anúncio); família que já tem anúncio ativo não ganha outro; estoque mínimo; produto sem custo fica de fora;
#   - pausados na publicidade NÃO são sugeridos: a pausa é decisão do vendedor (estoque, preço, venda no prejuízo);
#   - limite diário (`companies.ads_daily_budget_max`, Configurações → Ads) sobre o total das campanhas depois da rodada.
module Painel
  class AdsStructure
    TACOS_MID = 3.5 # meio da faixa alvo (3% a 4%)
    UPLIFT_PCT = 27.0 # aumento de vendas ao ativar Ads citado pela plataforma (26% a 28%)
    MIN_SHARE = 0.25
    MIN_FAMILIES = 3
    MIN_ORGANIC_UNITS = 3
    MIN_STOCK = 10
    MIN_EXCLUSIVE_BUDGET = 5 # abaixo disso não compensa campanha própria
    FLOOR_FACTOR = 1.35 # piso do ROAS Objetivo: equilíbrio + ~25% de folga (≈ 5% de lucro depois do Ads)
    STEP_FACTOR = 0.8 # cada descida do ROAS Objetivo: no máximo 20% por semana
    MAX_SUGGESTIONS = 7
    ROUND_DAYS = 7

    def self.call(account, analysis) = new(account, analysis).call

    def initialize(account, analysis)
      @account = account
      @company = account.company
      @families = analysis[:families]
      @campaigns = analysis[:campaigns]
      @decisions = analysis[:decisions] || []
      @max = @company.ads_daily_budget_max&.to_f
      @zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
    end

    def call
      @ledger = build_ledger
      @locked_keys, @locked_campaigns = locks
      @touched = [] # campanhas que já receberam mudança estrutural nesta rodada
      @used_keys = []
      @new_for_family = {} # family_id => nome da campanha exclusiva criada nesta rodada

      suggestions = []
      split_suggestions.each { |s| suggestions << s if s }
      move_suggestions.each { |s| suggestions << s if s }
      activate_suggestions.each { |s| suggestions << s if s }
      suggestions = suggestions.sort_by { |s| -s[:value].to_f }
      kept = suggestions.first(MAX_SUGGESTIONS)
      (suggestions - kept).each { |s| unpost(s) }
      plan = budget_plan(kept)
      { daily_max: @max, current_daily: current_daily.round(2), suggestions: kept, next_round: (suggestions - kept).map { |s| s.slice(:type, :title, :value) },
        plan: plan, round: round_info }
    end

    private

    # --- razão por campanha ---

    def build_ledger
      @campaigns.select { |c| c[:status] == "active" }.to_h do |c|
        [ c[:id], { id: c[:id], name: c[:name], new: false, budget_before: c[:daily_budget].to_f, budget_after: c[:daily_budget].to_f,
                    roas_before: c[:roas_target], roas_after: c[:roas_target], changes: [] } ]
      end
    end

    def post(campaign_key, attrs)
      entry = @ledger[campaign_key] ||= { id: nil, name: attrs[:name], new: true, budget_before: 0.0, budget_after: 0.0,
                                          roas_before: nil, roas_after: attrs[:roas], changes: [] }
      entry[:budget_after] += attrs[:budget].to_f
      entry[:roas_after] = attrs[:roas] if attrs.key?(:roas) && entry[:new]
      entry[:changes] << attrs[:change]
    end

    # Sugestão cortada pelo limite de quantidade: tira os lançamentos dela do razão.
    def unpost(s)
      (s[:postings] || []).each do |key, amount, change|
        entry = @ledger[key] or next
        entry[:budget_after] -= amount
        entry[:changes].delete(change)
        @ledger.delete(key) if entry[:new] && entry[:changes].empty?
      end
    end

    def current_daily = @ledger.values.reject { |e| e[:new] }.sum { |e| e[:budget_before] }

    # --- travas da rodada (decisões "Feito" dos últimos 7 dias) ---

    def locks
      recent = @decisions.select { |d| d[:status] == "feito" && d[:decided_at] > ROUND_DAYS.days.ago }
      keys = recent.map { |d| d[:key] }
      @lock_until = {}
      recent.each do |d|
        ids = if d[:key].start_with?("campaign:")
          [ d[:key].delete_prefix("campaign:").to_i ]
        else
          (fam = family_for_key(d[:key])) ? fam[:campaigns] : []
        end
        ids |= Array((d[:before] || {})["campaign_ids"] || (d[:before] || {})[:campaign_ids])
        until_on = d[:decided_at].in_time_zone(@zone).to_date + ROUND_DAYS
        ids.each { |id| @lock_until[id] = [ @lock_until[id], until_on ].compact.max }
      end
      [ keys, @lock_until.keys ]
    end

    def family_for_key(key)
      @families.find { |f| f[:key] == key } || (key.start_with?("item:") && @families.find { |f| f[:items].any? { |i| "item:#{i[:item_id]}" == key } })
    end

    def free_campaign?(id) = !@locked_campaigns.include?(id) && !@touched.include?(id)

    def round_info
      last = @decisions.select { |d| d[:status] == "feito" && d[:class] == "estrutura" }.map { |d| d[:decided_at] }.max
      next_at = last ? (last.in_time_zone(@zone).to_date + ROUND_DAYS) : @zone.today
      { cadence_days: ROUND_DAYS, last_round_at: last, next_round_on: next_at.iso8601,
        locked: @locked_campaigns.filter_map do |id|
          (c = @campaigns.find { |x| x[:id] == id }) &&
            { name: c[:name], until_on: @lock_until[id].iso8601,
              reason: "mudança marcada como feita: aguarda o aprendizado do ML e os 7 dias do \"depois\"" }
        end }
    end

    # --- dividir: família forte em campanha compartilhada ---

    def split_suggestions
      @campaigns.select { |c| c[:status] == "active" && c[:families] >= MIN_FAMILIES && c[:metrics][:cost] >= AdsAnalysis::RELEVANT_COST }.map do |c|
        next unless free_campaign?(c[:id])

        a = c[:auction]
        next unless a[:consistent] && (a[:lost_by_ad_rank].to_f >= 0.5 || a[:lost_by_budget].to_f >= 0.2)

        f = @families.select { |x| x[:campaigns] == [ c[:id] ] && !x[:untouchable] && !@locked_keys.include?(x[:key]) }
          .select { |x| real_equilibrium(x) && c[:metrics][:cost].positive? && x[:metrics][:cost] / c[:metrics][:cost] >= MIN_SHARE }
          .select { |x| x[:metrics][:roas].to_f >= real_equilibrium(x) && x[:sample][:cvr_ok] }
          .max_by { |x| x[:metrics][:cost] }
        next unless f

        eq = real_equilibrium(f)
        share = f[:metrics][:cost] / c[:metrics][:cost]
        fam_daily = f[:metrics][:cost] / AdsAnalysis::DAYS
        others_daily = (c[:metrics][:cost] - f[:metrics][:cost]) / AdsAnalysis::DAYS
        before = c[:daily_budget].to_f
        keep = round5_up(others_daily)
        moved = [ before - keep, 0 ].max
        budget = [ round5_up(fam_daily), moved ].max
        extra = (budget - moved).round
        start, floor = roas_path(c[:roas_target] || f[:metrics][:roas], f[:metrics][:roas], eq)
        name = "nova: #{f[:name].to_s.truncate(40)} (exclusiva)"
        change_out = "#{f[:name].to_s.truncate(40)} sai para campanha exclusiva"
        change_in = "recebe #{f[:name].to_s.truncate(40)}"
        post(c[:id], budget: -moved, change: change_out)
        post(name, name: name, budget: budget, roas: start, change: change_in)
        @touched << c[:id]
        @used_keys << f[:key]
        @new_for_family[f[:family_id]] = name if f[:family_id].present?
        {
          type: "dividir", title: f[:name], key: f[:key], item_ids: f[:items].select { |i| i[:status] == "active" }.map { |i| i[:item_id] },
          from_campaign: c[:name], to_campaign: name, daily_budget: budget, new_money: extra, frees_from: { campaign_id: c[:id], amount: moved },
          origin_budget_after: before - moved, roas_target: start, roas_floor: floor, keep_origin_roas: c[:roas_target],
          value: f[:metrics][:revenue].round(2),
          postings: [ [ c[:id], -moved, change_out ], [ name, budget, change_in ] ],
          rationale: "Concentra #{(share * 100).round}% do gasto de #{c[:name]} (#{brl(fam_daily)}/dia de #{brl(fam_daily + others_daily)}/dia) com ROAS #{f[:metrics][:roas]}, acima do equilíbrio real #{eq}; a campanha perde #{pct(a[:lost_by_ad_rank])} por classificação e #{pct(a[:lost_by_budget])} por orçamento, e o ROAS Objetivo dela (#{c[:roas_target] || '—'}) é alto por causa das outras famílias. Sozinha, a família pode baixar o ROAS Objetivo e disputar mais exibições.",
          expected: "Campanha nova com #{brl(budget)}/dia e ROAS Objetivo #{start}, descendo até no máximo 20% por semana se o resultado se mantiver, nunca abaixo de #{floor}. #{c[:name]} fica com #{brl(before - moved)}/dia (o que as outras famílias gastaram por dia) e mantém o ROAS Objetivo #{c[:roas_target] || '—'}.#{extra.positive? ? " Pede #{brl(extra)}/dia a mais que hoje." : ''}",
          check_before: "estoque da família; criar a campanha e mover os anúncios no Seller Center (o histórico fica no anúncio); ~7 dias de aprendizado"
        }
      end
    end

    # --- mover: família abaixo do equilíbrio em campanha de crescimento ---

    def move_suggestions
      @families.select { |f| !f[:untouchable] && f[:signals].any? { |s| s[:type] == "abaixo_do_equilibrio" } }.map do |f|
        next if @locked_keys.include?(f[:key]) || @used_keys.include?(f[:key])

        c = @campaigns.find { |x| f[:campaigns].include?(x[:id]) && x[:status] == "active" }
        next unless c && c[:families] >= 2 && free_campaign?(c[:id])

        eq = real_equilibrium(f) or next
        next if c[:roas_target].to_f >= eq * FLOOR_FACTOR # a campanha já é rentável para esta família

        daily = [ round5_up(f[:metrics][:cost] / AdsAnalysis::DAYS), 5 ].max
        target = (eq * 1.5).round(1).clamp(1.0, 35.0)
        name = "nova: Rentabilidade (ROAS Objetivo #{target})"
        change_out = "#{f[:name].to_s.truncate(40)} sai (abaixo do equilíbrio)"
        change_in = "recebe #{f[:name].to_s.truncate(40)}"
        post(c[:id], budget: -daily, change: change_out)
        post(name, name: name, budget: daily, roas: target, change: change_in)
        @touched << c[:id]
        @used_keys << f[:key]
        {
          type: "mover", title: f[:name], key: f[:key], item_ids: f[:items].select { |i| i[:status] == "active" }.map { |i| i[:item_id] },
          from_campaign: c[:name], to_campaign: name, daily_budget: daily, new_money: 0, frees_from: { campaign_id: c[:id], amount: daily },
          origin_budget_after: c[:daily_budget].to_f - daily, roas_target: target, roas_floor: target, keep_origin_roas: c[:roas_target],
          value: f[:signals].find { |s| s[:type] == "abaixo_do_equilibrio" }[:value],
          postings: [ [ c[:id], -daily, change_out ], [ name, daily, change_in ] ],
          rationale: "ROAS #{f[:metrics][:roas]} abaixo do equilíbrio real #{eq} dentro de #{c[:name]} (ROAS Objetivo #{c[:roas_target] || '—'}). Numa campanha de rentabilidade, com ROAS Objetivo #{target}, o lance só sobe quando a venda paga a margem.",
          expected: "Corta o investimento que hoje sai no prejuízo; #{c[:name]} fica com #{brl(c[:daily_budget].to_f - daily)}/dia.",
          check_before: "custo e preço da família (se a margem subir, nem precisa mover)"
        }
      end
    end

    # --- ativar: fora de campanha com potencial ---

    def activate_suggestions
      idle = @account.ml_ad_items.where(status: "idle").to_a
      return [] if idle.empty?

      metrics = ItemMetric.where(ml_account_id: @account.id, item_id: idle.map(&:item_id)).index_by(&:item_id)
      economics = ItemEconomics.for_page(@account, metrics.values)
      active_families = @families.select { |f| f[:n_active].to_i.positive? }.map { |f| f[:family_id] }.compact
      seen_families = []
      idle.map do |i|
        key = "item:#{i.item_id}"
        next if @locked_keys.include?(key)

        m = metrics[i.item_id]
        eco = economics[i.item_id]
        next unless m && eco && eco[:cost] && eco[:net_profit_pct].to_f.positive? && m.stock.to_i >= MIN_STOCK
        next unless i.recommended || m.units_30d.to_i >= MIN_ORGANIC_UNITS
        next if i.family_id.present? && (active_families.include?(i.family_id) || seen_families.include?(i.family_id))

        seen_families << i.family_id if i.family_id.present?
        daily_rev = m.revenue_30d.to_f / 30
        budget = [ (daily_rev * TACOS_MID / 100).round, 1 ].max
        eq = (100.0 / eco[:net_profit_pct]).round(2)
        dest = destination(i, eq, budget) or next

        change = "entra #{i.title.to_s.truncate(40)}"
        post(dest[:key], name: dest[:name], budget: budget, roas: dest[:roas], change: change)
        value = (daily_rev * UPLIFT_PCT / 100 * AdsAnalysis::DAYS).round(2)
        {
          type: "ativar", title: i.title, key: key, item_ids: [ i.item_id ], from_campaign: nil,
          to_campaign: dest[:name], daily_budget: budget, new_money: budget, frees_from: nil,
          roas_target: dest[:new] ? dest[:roas] : nil, roas_floor: dest[:new] ? (eq * FLOOR_FACTOR).round(1) : nil,
          keep_origin_roas: dest[:new] ? nil : dest[:roas], value: value,
          postings: [ [ dest[:key], budget, change ] ],
          rationale: "#{i.recommended ? 'O ML marca como recomendado para anunciar; vende' : 'Vende'} #{m.units_30d} un. em 30 dias sem Ads (#{brl(m.revenue_30d)}), margem bruta #{eco[:net_profit_pct].round(1)}% (equilíbrio #{eq}), #{m.stock} em estoque. #{brl(budget)}/dia mantém o TACOS em ~#{TACOS_MID}% sobre a receita atual.#{dest[:new] ? '' : " Na campanha #{dest[:name]} vale o ROAS Objetivo dela (#{dest[:roas]}), que fica acima de 1,2 × o equilíbrio deste anúncio."}",
          expected: "Potencial de +#{UPLIFT_PCT.round}% nas vendas (média citada pela plataforma; estimativa), ou #{brl(value)} em 7 dias.",
          check_before: "estoque (cobertura) e preço; revisar em 7 dias"
        }
      end
    end

    # Para onde vai o anúncio ativado: a campanha nova da mesma família criada nesta rodada; senão uma campanha ativa,
    # não travada, do mesmo tipo de produto cujo ROAS Objetivo cobre o equilíbrio dele com folga; senão exclusiva (se o
    # orçamento justificar).
    def destination(item, eq, budget)
      if item.family_id.present? && (name = @new_for_family[item.family_id]) && @ledger[name]
        return { key: name, name: name, roas: @ledger[name][:roas_after], new: true }
      end

      same = @account.ml_ad_items.where(status: "active", domain_id: item.domain_id).where.not(campaign_id: nil).distinct.pluck(:campaign_id)
      best = same.filter_map { |cid| @campaigns.find { |c| c[:id] == cid && c[:status] == "active" } }
        .select { |c| free_campaign?(c[:id]) && c[:roas_target].to_f >= eq * 1.2 }
        .max_by { |c| c[:metrics][:roas].to_f }
      return { key: best[:id], name: best[:name], roas: best[:roas_target], new: false } if best
      return nil if budget < MIN_EXCLUSIVE_BUDGET

      start = [ (eq * 2).round(1), 3.3 ].max
      name = "nova: #{item.title.to_s.truncate(40)} (exclusiva)"
      { key: name, name: name, roas: start, new: true }
    end

    # Equilíbrio só com custo real (sem a referência 3,33 de produto sem custo).
    def real_equilibrium(f)
      eco = f[:economics]
      eco && eco[:cost] && eco[:roas_equilibrio]
    end

    # ROAS Objetivo da campanha nova: começa 20% abaixo do praticado (sem passar do atual da campanha) e o piso é
    # equilíbrio × 1,35.
    def roas_path(current_target, practiced, eq)
      floor = [ (eq * FLOOR_FACTOR).round(1), 3.3 ].max
      goal = @account.ads_roas_goal # ROAS Objetivo do vendedor: piso das campanhas sugeridas
      floor = [ floor, goal ].max if goal
      start = [ ([ current_target.to_f, practiced.to_f ].min * STEP_FACTOR).round, floor ].max
      [ start.to_f.clamp(1.0, [ 35.0, floor ].max), floor ]
    end

    def round5_up(v) = ((v.to_f / 5).ceil * 5).to_f

    # --- limite diário ---

    # Total das campanhas depois da rodada contra o limite. Dinheiro novo (ativar, ou dividir que pede mais que o
    # realocado) que não cabe fica marcado; campanhas abaixo do equilíbrio, livres nesta rodada, cedem verba.
    def budget_plan(suggestions)
      current = current_daily
      after = @ledger.values.sum { |e| e[:budget_after] }
      suggestions.each { |s| s[:within_limit] = true }
      reductions = []
      if @max && after > @max + 0.01
        over = after - @max
        suggestions.select { |s| s[:new_money].to_f.positive? }.sort_by { |s| s[:value].to_f }.each do |s|
          break if over <= 0

          s[:within_limit] = false
          s[:note] = "não cabe no limite diário de #{brl(@max)}"
          over -= s[:new_money].to_f
        end
        @campaigns.select { |c| c[:status] == "active" && free_campaign?(c[:id]) && c[:equilibrium] && c[:metrics][:roas].to_f < c[:equilibrium] && c[:daily_budget].to_f.positive? }
          .sort_by { |c| c[:metrics][:roas].to_f }.each do |c|
          needed = suggestions.reject { |s| s[:within_limit] }.sum { |s| s[:new_money].to_f }
          break if needed <= 0

          cut = [ (c[:daily_budget].to_f * 0.5).round, needed.ceil ].min
          next if cut <= 0

          post(c[:id], budget: -cut, change: "reduz #{brl(cut)}/dia (abaixo do equilíbrio)")
          @touched << c[:id]
          reductions << { type: "reduzir", title: "Campanha #{c[:name]}", key: "campaign:#{c[:id]}", item_ids: [], from_campaign: c[:name], to_campaign: nil,
                          daily_budget: -cut, new_money: -cut, frees_from: nil, roas_target: nil, roas_floor: nil, keep_origin_roas: c[:roas_target],
                          value: nil, within_limit: true,
                          rationale: "ROAS #{c[:metrics][:roas]} abaixo do equilíbrio #{c[:equilibrium]}: reduzir o orçamento diário de #{brl(c[:daily_budget])} para #{brl(c[:daily_budget].to_f - cut)} libera #{brl(cut)}/dia dentro do limite.",
                          expected: "Libera verba sem passar do limite.", check_before: "famílias dentro da campanha que ainda rendem" }
          freed = cut
          suggestions.reject { |s| s[:within_limit] }.sort_by { |s| -s[:value].to_f }.each do |s|
            next if s[:new_money].to_f > freed

            s[:within_limit] = true
            s[:note] = "cabe no limite só com a redução sugerida em #{c[:name]}"
            freed -= s[:new_money].to_f
          end
        end
      end
      # Dinheiro novo que ficou fora do limite sai do razão (a campanha de destino não recebe)
      suggestions.reject { |s| s[:within_limit] }.each { |s| unpost(s) }
      suggestions.concat(reductions)
      suggestions.each { |s| s.delete(:postings) }
      after = @ledger.values.sum { |e| e[:budget_after] }
      new_money = suggestions.select { |s| s[:within_limit] && s[:new_money].to_f.positive? }.sum { |s| s[:new_money].to_f }
      { current_daily: current.round(2), new_daily: new_money.round(2),
        reallocated_daily: suggestions.select { |s| s[:frees_from] }.sum { |s| s[:frees_from][:amount].to_f }.round(2),
        after_daily: after.round(2), daily_max: @max, fits: @max.nil? || after <= @max + 0.01,
        campaigns: @ledger.values.select { |e| e[:changes].any? }.map { |e| e.merge(budget_before: e[:budget_before].round(2), budget_after: e[:budget_after].round(2)) },
        note: @max.nil? ? "Informe o limite máximo de investimento diário em Configurações → Ads para o plano respeitar o teto." : nil }
    end

    def brl(v) = ActiveSupport::NumberHelper.number_to_currency(v.to_f, unit: "R$", separator: ",", delimiter: ".")
    def pct(v) = "#{(v.to_f * 100).round}%"
  end
end
