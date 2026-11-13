# Ads > Análise (pedido do usuário em 09/11/2026): cada ação da fila explicada para quem não é especialista em
# publicidade: "o que está acontecendo" (com os números da conta, em reais) e o "passo a passo" de onde clicar no
# Mercado Livre e no Lunna. Só texto; não muda nenhum cálculo.
module Painel
  module AdsExplain
    ML_PATH = "No Mercado Livre: Minha conta › Publicidade › Product Ads › Campanhas"

    def self.call(entry, family: nil, campaign: nil)
      m = family&.dig(:metrics) || campaign&.dig(:metrics) || {}
      e = family&.dig(:economics) || {}
      ids = Array(entry[:item_ids])
      listings = ids.any? ? "#{ids.size == 1 ? 'o anúncio' : "os #{ids.size} anúncios"} listados acima" : "os anúncios da campanha"
      # variações do mesmo anúncio pai: o ML só pausa a publicidade do anúncio inteiro
      parent = ids.size > 1 ? "o anúncio inteiro (as #{ids.size} variações listadas acima saem juntas; o Mercado Livre não pausa uma variação sozinha)" : "o anúncio"
      camp = Array(entry[:campaigns]).first || campaign&.dig(:name)
      period = "nos últimos 7 dias"
      text =
        case entry[:signal]
        when "abaixo_do_equilibrio"
          spent = m[:cost].to_f
          sold = m[:revenue].to_f
          margin = e[:margin_pct].to_f
          kept = sold * margin / 100.0
          {
            situation: "#{period.capitalize} você investiu #{brl(spent)} em anúncios pagos destes produtos e eles venderam " \
                       "#{brl(sold)}. Cada venda deixa cerca de #{pct(margin)} de lucro antes da publicidade (preço menos custo, " \
                       "tarifa, frete e imposto), ou seja, #{brl(kept)} — menos do que os #{brl(spent)} gastos com anúncio. " \
                       "Resultado: a publicidade está tirando dinheiro do seu bolso. Para empatar, cada R$ 1 investido precisaria " \
                       "trazer #{brl(e[:roas_equilibrio])} em vendas (hoje traz #{brl(m[:roas])}).",
            steps: [
              "Confira se o custo destes produtos está certo no Lunna (Produtos). Custo errado muda toda a conta.",
              "Veja se dá para subir o preço sem perder vendas (Curva ABC › anúncio › Preço, ou Promoções). Com mais margem, a publicidade volta a se pagar.",
              "Se não der para subir a margem, pause a publicidade de #{parent}: #{ML_PATH} › #{camp || 'campanha'} › marque o anúncio › Pausar. Não exclua o anúncio, só a publicidade.",
              "Volte ao Lunna e clique em \"Marcar como feito\". Em 7 dias o Lunna mostra se o lucro melhorou."
            ]
          }
        when "abaixo_do_roas_objetivo"
          p = entry[:plan] || {}
          goal = Array(p[:path]).last
          if p[:at_goal]
            steps = Array(p[:levers]).map { |l| "Subir a conversão: #{l[:detail]}. Converter mais aumenta o ROAS sem perder exibições." }
            steps << "Não mexa no ROAS objetivo nesta semana: o ML está reaprendendo os lances com o novo alvo (#{p[:current]})."
            steps << "Trava de segurança: se as vendas totais do anúncio (com e sem Ads) caírem mais de #{p[:sales_drop_limit]}% em relação à semana anterior, " \
                     "volte o ROAS objetivo para #{p[:step_back]} (#{ML_PATH} › #{p[:campaign]} › Editar) e segure 2 semanas antes de tentar #{goal} de novo."
            steps << "Em 7 dias o Lunna mostra aqui o ROAS e as vendas já com o novo alvo."
            return {
              situation: "O ROAS objetivo da campanha #{p[:campaign]} já foi para #{p[:current]}, o seu alvo. Os números dos últimos 7 dias " \
                         "(cada R$ 1 trouxe #{brl(m[:roas])}) ainda são do lance antigo; agora é deixar o ML ajustar e vigiar as vendas.",
              steps: steps
            }
          end
          steps = []
          if p[:shared]
            steps << "Esta campanha tem outros produtos: subir o ROAS objetivo afeta todos. Se só este estiver abaixo do alvo, " \
                     "separe-o numa campanha própria primeiro (veja Estrutura de campanhas)."
          end
          Array(p[:levers]).each { |l| steps << "Subir a conversão: #{l[:detail]}. Converter mais aumenta o ROAS sem perder exibições." }
          steps << if Array(p[:path]).size > 1
            "Esta semana: #{ML_PATH} › #{p[:campaign] || camp || 'campanha'} › Editar › ROAS objetivo de #{p[:current] || '—'} para #{p[:next]}. " \
              "Não pule direto para #{goal}: o ML reaprende os lances a cada mudança, e um salto grande corta as exibições de uma vez."
          else
            "Esta semana: #{ML_PATH} › #{p[:campaign] || camp || 'campanha'} › Editar › ROAS objetivo de #{p[:current] || '—'} para #{p[:next]}. " \
              "É um degrau só (até 25% acima do objetivo atual), então já dá para ir direto ao seu alvo."
          end
          if Array(p[:path]).size > 1
            steps << "Nas semanas seguintes, um degrau por semana: #{Array(p[:path]).drop(1).join(' → ')} (cerca de #{p[:weeks]} semanas até #{goal}). O Lunna mostra o próximo degrau aqui."
          end
          steps << "Trava de segurança: se as vendas totais do anúncio (com e sem Ads) caírem mais de #{p[:sales_drop_limit] || 30}% depois de um degrau, volte ao degrau anterior e segure por 2 semanas."
          steps << "Depois de cada mudança, clique em \"Marcar como feito\" no Lunna para acompanhar o antes e depois."
          {
            situation: "#{period.capitalize} você investiu #{brl(m[:cost])} em anúncios pagos destes produtos e eles venderam " \
                       "#{brl(m[:revenue])}: cada R$ 1 trouxe #{brl(m[:roas])}. Dá lucro (o equilíbrio é #{brl(e[:roas_equilibrio])}), " \
                       "mas está abaixo do seu ROAS Objetivo (#{goal}). O caminho é chegar lá em degraus, sem derrubar as vendas, e " \
                       "subindo a conversão ao mesmo tempo.",
            steps: steps
          }
        when "gasto_sem_receita"
          {
            situation: "#{period.capitalize} você investiu #{brl(m[:cost])} em anúncios pagos destes produtos e eles não venderam " \
                       "nada pela publicidade. As pessoas clicam (#{m[:clicks].to_i} cliques), mas não compram.",
            steps: [
              "Abra o anúncio e compare com o \"Mais vendido\" da categoria: preço, frete, fotos e título. Normalmente o motivo está aí.",
              "Corrija o que estiver pior (preço, frete grátis, capa, ficha técnica).",
              "Se em 30 dias continuar sem vender, pause a publicidade de #{parent}: #{ML_PATH} › #{camp || 'campanha'} › marque o anúncio › Pausar.",
              "Clique em \"Marcar como feito\" no Lunna para acompanhar."
            ]
          }
        when "saiu_do_ar_com_historico"
          {
            situation: "Estes anúncios vendiam pela publicidade, mas saíram do ar (pausados, sem estoque ou com problema) e você " \
                       "está deixando de vender.",
            steps: [
              "Abra cada anúncio listado no Mercado Livre e veja o motivo: sem estoque, pausado ou em revisão.",
              "Reponha o estoque (Olist/Full) ou reative o anúncio.",
              "Clique em \"Marcar como feito\" no Lunna."
            ]
          }
        when "familia_com_multiplos_anuncios_ativos"
          {
            situation: "Você tem dois anúncios separados do mesmo produto (por exemplo, catálogo e tradicional) com publicidade ligada, e eles disputam o mesmo comprador. " \
                       "Um deles (#{family&.dig(:signals)&.find { |x| x[:type] == entry[:signal] }&.dig(:best) || 'o melhor'}) dá bem mais retorno que o outro.",
            steps: [
              "Confira se os dois anúncios têm o mesmo preço e estoque.",
              "#{ML_PATH} › #{camp || 'campanha'} › pause a publicidade do anúncio com pior resultado e mantenha a do melhor.",
              "Não exclua o anúncio pausado na publicidade: ele continua vendendo sem anúncio pago.",
              "Clique em \"Marcar como feito\" no Lunna."
            ]
          }
        when "exposicao_perdida_por_orcamento"
          {
            situation: "A campanha #{camp} dá lucro, mas o dinheiro diário acaba antes do fim do dia e o anúncio deixa de aparecer " \
                       "para muitos compradores. Mais orçamento = mais vendas lucrativas.",
            steps: [
              "Confira se há estoque suficiente para vender mais.",
              "#{ML_PATH} › #{camp} › Editar › aumente o orçamento diário (a sugestão está na Ação acima). Não mexa no ROAS objetivo.",
              "Clique em \"Marcar como feito\" no Lunna e reavalie em 7 dias."
            ]
          }
        when "exposicao_perdida_por_ad_rank"
          {
            situation: "Os anúncios da campanha #{camp} perdem espaço para concorrentes porque o Mercado Livre os considera menos " \
                       "atrativos (capa, ficha, preço ou lance). Aumentar o orçamento não resolve.",
            steps: [
              "Melhore capa, ficha técnica e preço dos anúncios que mais gastam (veja em Curva ABC).",
              "Se a margem permitir, baixe o ROAS objetivo da campanha: #{ML_PATH} › #{camp} › Editar.",
              "Clique em \"Marcar como feito\" no Lunna."
            ]
          }
        when "capa_suspeita", "impressao_sem_clique"
          {
            situation: "Os anúncios aparecem bastante, mas quase ninguém clica. Normalmente é a foto principal (capa) ou o título que não chama atenção.",
            steps: [
              "Troque a foto principal por uma de fundo branco, 1200×1200, com o produto inteiro (Curva ABC › Gerar fotos ajuda).",
              "Revise o título com as palavras que o comprador busca.",
              "Clique em \"Marcar como feito\" no Lunna."
            ]
          }
        when "idle_recomendado"
          {
            situation: "O Mercado Livre indica estes anúncios como bons para publicidade, mas eles ainda não estão em nenhuma campanha.",
            steps: [
              "Confira estoque e margem dos produtos.",
              "#{ML_PATH} › escolha uma campanha › Adicionar anúncios › selecione #{listings}.",
              "Clique em \"Marcar como feito\" no Lunna."
            ]
          }
        end
      text || {}
    end

    def self.brl(v)
      return "—" if v.nil?

      int, dec = format("%.2f", v.to_f).split(".")
      "R$ #{int.reverse.scan(/\d{1,3}/).join('.').reverse.then { |x| v.to_f.negative? ? "-#{x}" : x }},#{dec}"
    end
    def self.pct(v) = "#{format('%.1f', v.to_f).tr('.', ',')}%"
  end
end
