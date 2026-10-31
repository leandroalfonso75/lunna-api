# Diagnóstico de uma família (produto) ou de uma campanha de Product Ads, no formato do plugin "Agente ads ml":
# alvo e escopo, veredito em uma frase (a causa mais provável), evidência em números, o que foi descartado e por quê,
# o que fazer em ordem (com prazo), o que NÃO fazer e a incerteza. Só recomenda. Trabalha sobre o resultado de
# Painel::AdsAnalysis (mesma janela de 7 dias fechados) e as árvores de decisão por sintoma (docs/secoes/ads.md).
module Painel
  class AdsDiagnosis
    def self.call(account, family: nil, campaign_id: nil)
      analysis = AdsAnalysis.call(account)
      new(account, analysis).call(family: family, campaign_id: campaign_id)
    end

    def initialize(account, analysis)
      @account = account
      @analysis = analysis
      @health = analysis[:health]
    end

    def call(family: nil, campaign_id: nil)
      return diagnose_campaign(campaign_id.to_i) if campaign_id.present?

      fam = @analysis[:families].find { |f| f[:key] == family.to_s }
      return nil unless fam

      diagnose_family(fam)
    end

    private

    # --- família ---

    def diagnose_family(f)
      m = f[:metrics]
      prev = f[:previous]
      evidence = [
        "Investimento #{brl(m[:cost])} (antes #{brl(prev[:cost])}); receita por Ads #{brl(m[:revenue])} (antes #{brl(prev[:revenue])}).",
        "ROAS #{m[:roas] || '—'} (antes #{prev[:roas] || '—'}); ACOS #{m[:acos] ? "#{m[:acos]}%" : '—'}.",
        "#{m[:clicks]} cliques em #{m[:prints]} impressões (CTR #{m[:ctr] ? "#{m[:ctr]}%" : '—'}; média da conta #{@health[:ctr] ? "#{@health[:ctr]}%" : '—'}); conversão #{m[:cvr] ? "#{m[:cvr]}%" : '—'} (conta #{@health[:cvr] ? "#{@health[:cvr]}%" : '—'})."
      ]
      eq = f.dig(:economics, :roas_equilibrio)
      evidence << (eq ? "ROAS de Equilíbrio #{eq} (margem bruta #{f[:economics][:margin_pct]}%, custo #{brl(f[:economics][:cost])}, preço #{brl(f[:economics][:price])})." : "Sem custo cadastrado: ROAS de Equilíbrio não calculável; não é possível afirmar lucro.")
      evidence << "#{f[:n_active]} anúncio(s) ativo(s) de #{f[:n_items]}; campanhas: #{f[:items].map { |i| i[:campaign] }.compact.uniq.join(', ').presence || 'nenhuma'}."

      discarded = []
      uncertainty = []
      types = f[:signals].map { |s| s[:type] }
      sample_ok = f[:sample][:cvr_ok] || f[:sample][:ctr_ok]
      uncertainty << "Amostra insuficiente (#{m[:clicks]} cliques, #{m[:prints]} impressões): o veredito é hipótese, não conclusão." unless sample_ok
      uncertainty << f[:untouchable][:reason].capitalize + "." if f[:untouchable]
      uncertainty << "Sem custo cadastrado, não dá para dizer se a venda por Ads dá lucro." unless eq

      verdict, symptom, actions, avoid = pick_family_symptom(f, types, discarded)
      {
        scope: { kind: "familia", key: f[:key], name: f[:name], items: f[:n_items], active: f[:n_active], period: @analysis[:period] },
        symptom: symptom, verdict: verdict, evidence: evidence, discarded: discarded, actions: actions, avoid: avoid,
        uncertainty: uncertainty, signals: f[:signals], items: f[:items]
      }
    end

    # => [veredito, sintoma, ações ordenadas, o que não fazer]
    def pick_family_symptom(f, types, discarded)
      m = f[:metrics]
      prev = f[:previous]
      eq = f.dig(:economics, :roas_equilibrio)

      # bloqueadores primeiro: fora do ar com histórico e divisão de verba entre anúncios
      if types.include?("saiu_do_ar_com_historico")
        s = f[:signals].find { |x| x[:type] == "saiu_do_ar_com_historico" }
        return [ "Receita parada: anúncio(s) desta família saíram do ar (#{s[:item_ids].join(', ')}) carregando #{brl(s[:value])} do período. É estoque ou catálogo, não lance.",
                 "saiu_do_ar", [ act("Conferir no ML a situação do(s) anúncio(s) e o estoque (Olist e Full); reativar ou repor.", "imediato"),
                                 act("Só depois disso avaliar o desempenho de Ads da família.", "7 dias") ],
                 [ "Mexer em lance ou orçamento enquanto o anúncio está fora do ar." ] ]
      end
      if types.include?("gasto_sem_receita")
        discarded << "Não é orçamento: o problema é não converter, não falta de verba."
        return [ "Investimento sem retorno: #{brl(m[:cost])} gastos e nenhuma venda por Ads. A causa mais provável é oferta pouco competitiva na página (preço, frete, fotos) ou anúncio que o algoritmo já classificou como fraco.",
                 "gasta_e_nao_vende", [ act("Comparar preço, frete e fotos com o 'Mais vendido' da categoria; ajustar a oferta ou migrar para Full/Flex.", "imediato"),
                                        act("Aguardar o ciclo de 30 dias desde a criação; se seguir zerado, pausar a publicidade do(s) anúncio(s) (não excluir: perde reviews e relevância).", "30 dias") ],
                 [ "Manter o anúncio ativo esperando melhora natural.", "Aumentar lance ou orçamento." ] ]
      end
      if m[:prints] >= AdsAnalysis::MIN_PRINTS && (m[:clicks].zero? || (@health[:ctr] && m[:ctr].to_f < @health[:ctr] * 0.6))
        discarded << "Não é exposição: há #{m[:prints]} impressões no período."
        return [ "CTR baixo (#{m[:ctr] || 0}% contra #{@health[:ctr]}% da conta): o anúncio aparece e não atrai. Causa provável: imagem principal fraca ou título sem os termos que o comprador usa.",
                 "ctr_baixo", [ act("Trocar a capa (1200×1200, fundo branco, sem marca d'água).", "7 dias"), act("Reescrever o título com os termos reais de busca.", "7 dias") ],
                 [ "Aumentar lance ou baixar o ROAS Objetivo: o problema é atratividade, não exposição." ] ]
      end
      if m[:clicks] >= AdsAnalysis::MIN_CLICKS && (m[:cvr].to_f.zero? || (@health[:cvr] && m[:cvr].to_f < @health[:cvr] * 0.5))
        discarded << "Não é CTR: #{m[:clicks]} cliques no período (#{m[:ctr]}%)."
        return [ "Clica e não compra: conversão #{m[:cvr] || 0}% contra #{@health[:cvr]}% da conta. Causa provável: perda de competitividade na página (preço, parcelamento, prazo), ficha técnica incompleta ou atendimento lento.",
                 "cvr_baixa", [ act("Conferir preço e parcelamento contra o líder da categoria no momento do clique.", "imediato"), act("Completar a ficha técnica (atributos obrigatórios).", "7 dias"), act("Responder perguntas em menos de 1 hora.", "7 dias") ],
                 [ "Reduzir lances: esconde o sintoma sem curar a causa." ] ]
      end
      if m[:roas] && prev[:roas] && prev[:roas].positive? && m[:roas] < prev[:roas] * 0.7
        return [ "ROAS caiu de #{prev[:roas]} para #{m[:roas]} de uma semana para outra. Causa provável: perda de reputação ou qualidade orgânica; depois, sazonalidade ou concorrência inflando o CPC (CPC #{m[:cpc] || '—'} contra #{prev[:cpc] || '—'}).",
                 "roas_caiu", [ act("Conferir a reputação da conta (medalha, reclamações, cancelamentos) e corrigir logística/atendimento primeiro.", "imediato"), act("Conferir preço e concorrência; se for evento sazonal, ajustar o ROAS Objetivo temporariamente.", "7 dias") ],
                 [ "Reduzir o orçamento como primeira reação: paralisa as vendas que restam." ] ]
      end
      if types.include?("abaixo_do_equilibrio")
        return [ "ROAS #{m[:roas]} abaixo do ROAS de Equilíbrio #{eq}: cada venda por Ads sai no prejuízo com os custos atuais (margem bruta #{f[:economics][:margin_pct]}%).",
                 "abaixo_do_equilibrio", [ act("Rever custo e preço: a margem bruta precisa subir ou o ROAS precisa passar de #{eq}.", "imediato"), act("Se não houver como, pausar a publicidade desta família (sem excluir anúncios).", "30 dias") ],
                 [ "Baixar o lance como primeira ação para melhorar o ACOS: corta exposição e mantém o problema." ] ]
      end
      if types.include?("familia_com_multiplos_anuncios_ativos")
        s = f[:signals].find { |x| x[:type] == "familia_com_multiplos_anuncios_ativos" }
        return [ "A verba do produto está repartida entre anúncios de ROAS diferente, e o maior gasto está no pior (#{s[:worst]}).",
                 "multiplos_ativos", [ act("Concentrar a verba no anúncio #{s[:best]} e pausar a publicidade do #{s[:worst]}.", "7 dias") ],
                 [ "Excluir o anúncio pior: é irreversível (perde reviews e relevância)." ] ]
      end
      if eq && m[:roas] && m[:roas] >= [ eq * 2.5, 8.0 ].max
        return [ "ROAS muito alto (#{m[:roas]}) para um produto que provavelmente já lidera o orgânico: parte dessas vendas pode acontecer sem Ads (canibalização). As fontes não trazem teste validado; é inferência.",
                 "canibalizacao", [ act("Subir o ROAS Objetivo da campanha aos poucos e observar se o orgânico compensa a queda no pago (TACOS).", "7 dias") ],
                 [ "Pausar a campanha de uma vez: reduzir gradualmente para medir a elasticidade." ] ]
      end
      discarded << "Nenhum sintoma das árvores de decisão se encaixa com os números do período."
      [ "Sem sintoma claro: a família está dentro das regras no período#{eq ? " (ROAS #{m[:roas]} contra equilíbrio #{eq})" : ''}.",
        "sem_sintoma", [ act("Manter e reavaliar na próxima rodada.", "7 dias") ], [] ]
    end

    # --- campanha ---

    def diagnose_campaign(id)
      c = @analysis[:campaigns].find { |x| x[:id] == id }
      return nil unless c

      a = c[:auction]
      m = c[:metrics]
      evidence = [
        "Investimento #{brl(m[:cost])}; receita por Ads #{brl(m[:revenue])}; ROAS #{m[:roas] || '—'}; ACOS #{m[:acos] ? "#{m[:acos]}%" : '—'} contra benchmark da disputa #{a[:acos_benchmark] ? "#{a[:acos_benchmark]}%" : '—'}.",
        "Aparece em #{pct(a[:impression_share])} das oportunidades; perde #{pct(a[:lost_by_budget])} por orçamento e #{pct(a[:lost_by_ad_rank])} por classificação#{a[:consistent] == false ? ' (conferência dos shares não fecha: ler com cautela)' : ''}.",
        "Estratégia #{c[:strategy] || '—'}; ROAS Objetivo #{c[:roas_target] || '—'}; orçamento diário #{brl(c[:daily_budget])}; #{c[:families]} família(s) ativa(s) (#{c[:attribution]}); equilíbrio das famílias até #{c[:equilibrium] || '—'}."
      ]
      discarded = []
      uncertainty = []
      uncertainty << "Com várias famílias na campanha, o share é do conjunto, não de um produto." if c[:attribution] == "compartilhada"
      uncertainty << "Sem custo nas famílias, a comparação com o equilíbrio usa a referência 3,33." if c[:equilibrium].nil?

      spent_ratio = c[:daily_budget].to_f.positive? ? m[:cost] / (c[:daily_budget].to_f * AdsAnalysis::DAYS) : nil
      verdict, symptom, actions, avoid =
        if a[:consistent] && a[:lost_by_budget].to_f >= 0.20 && (c[:equilibrium] ? m[:roas].to_f >= c[:equilibrium] : m[:roas].to_f >= AdsAnalysis::REFERENCE_EQUILIBRIUM)
          discarded << "Não é classificação: a perda maior é por orçamento (#{pct(a[:lost_by_budget])})."
          [ "A campanha rende acima do equilíbrio e perde #{pct(a[:lost_by_budget])} das impressões por falta de verba.", "perde_por_orcamento",
            [ act("Aumentar o orçamento diário de #{brl(c[:daily_budget])} para #{brl((c[:daily_budget].to_f * 1.3).round)} (+30%).", "7 dias") ],
            [ "Mexer no ROAS Objetivo: o gargalo é verba, não lance." ] ]
        elsif a[:consistent] && a[:lost_by_ad_rank].to_f >= 0.50
          discarded << "Não é orçamento: só #{pct(a[:lost_by_budget])} das impressões se perdem por verba."
          [ "A campanha perde #{pct(a[:lost_by_ad_rank])} das impressões por classificação (Ad-Rank insuficiente): o lance travado pelo ROAS Objetivo ou a qualidade dos anúncios não ganha o leilão.", "perde_por_ad_rank",
            [ act("Melhorar capa, ficha técnica e preço dos anúncios de maior gasto.", "7 dias"),
              act("Baixar o ROAS Objetivo#{c[:roas_target] ? " de #{c[:roas_target]} para #{(c[:roas_target] * 0.8).round(1)}" : ''} para o lance subir, sem ficar abaixo do equilíbrio#{c[:equilibrium] ? " (#{c[:equilibrium]})" : ''}.", "7 dias") ],
            [ "Aumentar o orçamento: verba nova não compra posição quando a perda é por rank." ] ]
        elsif spent_ratio && spent_ratio < 0.7 && a[:lost_by_budget].to_f < 0.05 && (c[:roas_target].nil? || m[:roas].to_f >= c[:roas_target])
          [ "ROAS bom, mas a campanha não gasta o orçamento (#{(spent_ratio * 100).round}% do previsto): o ROAS Objetivo está conservador demais e trava o lance.", "nao_gasta",
            [ act("Diminuir o ROAS Objetivo (comparar com o benchmark #{a[:acos_benchmark] ? "ACOS #{a[:acos_benchmark]}%" : 'da disputa'}).", "7 dias") ],
            [ "Aumentar o orçamento diário: o sistema já não consegue gastar o atual." ] ]
        elsif c[:equilibrium] && m[:roas] && m[:roas] < c[:equilibrium]
          [ "ROAS #{m[:roas]} abaixo do equilíbrio das famílias (#{c[:equilibrium]}): a campanha vende no prejuízo com os custos atuais.", "abaixo_do_equilibrio",
            [ act("Olhar as famílias da campanha com sinal 'abaixo do equilíbrio' e rever preço/custo ou pausar a publicidade delas.", "imediato") ],
            [ "Baixar lance para reduzir o ACOS como primeira ação." ] ]
        else
          [ "Sem sintoma claro no período: ROAS #{m[:roas] || '—'}, perdas de exposição dentro do comum.", "sem_sintoma",
            [ act("Manter e reavaliar na próxima rodada.", "7 dias") ], [] ]
        end

      { scope: { kind: "campanha", key: "campaign:#{c[:id]}", name: c[:name], families: c[:families], period: @analysis[:period] },
        symptom: symptom, verdict: verdict, evidence: evidence, discarded: discarded, actions: actions, avoid: avoid,
        uncertainty: uncertainty, campaign: c }
    end

    def act(text, reassess) = { action: text, reassess: reassess }
    def brl(v) = ActiveSupport::NumberHelper.number_to_currency(v.to_f, unit: "R$ ", separator: ",", delimiter: ".")
    def pct(v) = v.nil? ? "—" : "#{(v.to_f * 100).round}%"
  end
end
