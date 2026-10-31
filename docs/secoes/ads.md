# Ads

Campanhas e anúncios de publicidade (**Product Ads**) do Mercado Livre dos últimos **3 meses**, com as métricas que a API entrega.

## O que mostra
- **Período:** Hoje, Ontem, 7, 30, 60 dias, 3 meses ou datas escolhidas (a API do Mercado Livre limita a consulta a 90
  dias). Campanhas, resumo e gráfico saem dos dados diários guardados; "Hoje" é atualizado a cada 30 minutos.
- **Resumo (8 cartões):** investimento, vendas por Ads, ACOS, ROAS, cliques, impressões, conversão e vendas sem Ads
  (orgânicas). Cada cartão compara com o período anterior de mesmo tamanho, quando há dados (▲/▼ verde ou vermelho
  conforme subir seja bom ou ruim).
- **Gráfico:** vendas por Ads e investimento, dia a dia.
- **Aba Campanhas:** nome, situação, estratégia, investimento, vendas, ACOS (com a meta da campanha), ROAS, cliques,
  CTR, CPC, conversão e orçamento diário. O ACOS fica verde dentro da meta, amarelo até 20% acima e vermelho acima disso.
  Ao clicar abre a configuração (metas, orçamento, datas), o resultado (vendas diretas, indiretas e orgânicas) e um
  gráfico por dia, com o atalho "Ver os anúncios ativos desta campanha" (abre a aba Anúncios já filtrada pela campanha e
  por "Ativos").
- **Aba Anúncios:** os anúncios em campanha, com foto, campanha, investimento, vendas, ACOS, ROAS, unidades, cliques e
  impressões. Filtros por campanha, situação (ativo/pausado), desempenho e busca por título/código; ordenação por qualquer
  coluna; totais do filtro no rodapé.
- **Sinais por anúncio:** "Gastou e não vendeu" (investimento ≥ R$ 10 e nenhuma unidade), "ACOS acima da meta" (mais de
  20% acima da meta da campanha) e "Dentro da meta".

## Contas (feitas na API, nunca somadas entre campanhas)
`ACOS = investimento ÷ vendas por Ads × 100`, `ROAS = vendas ÷ investimento`, `CTR = cliques ÷ impressões × 100`,
`CPC = investimento ÷ cliques`, `conversão = unidades vendidas por Ads ÷ cliques × 100`. Implementado em
`Painel::AdsQuery`. Os totais de uma campanha e do resumo vêm da soma dos dias. Os dos anúncios vêm das janelas guardadas
de 7, 30 e 90 dias; os outros períodos (Hoje, Ontem, 60 dias e datas escolhidas) são consultados no Mercado Livre na
hora, em cerca de 4 segundos, e ficam 5 minutos em cache. Se o Mercado Livre não responder, a tela avisa.

## Análise (aba "Análise", `Painel::AdsAnalysis`, `GET /api/ads/analysis`)
Ferramenta de decisão baseada no plugin "Agente ads ml" (referência, não cópia). **Só recomenda**: nunca altera campanha;
a execução é no Seller Center. Decisões do usuário (30/10): só recomendar; janela de 7 dias; até 7 ações; TACOS alvo 3% a 4%.
- **Janela:** os últimos 7 dias fechados (o dia corrente consolida às 10:00) e os 7 anteriores para comparar; 30 dias
  para maturação. Anúncios: `ml_ad_item_dailies`; orgânico: `ml_ad_daily_metrics.organic_amount`; leilão: `ml_ad_campaigns.auction`.
- **Unidade:** a família (`family_id`); um produto com 4 anúncios não são 4 produtos.
- **Saúde:** investimento, receita por Ads, ROAS, ACOS, **TACOS** = investimento ÷ (receita por Ads + orgânica), share de
  Ads, cada um contra os 7 dias anteriores. TACOS: até 4% ok, até 6% atenção, acima ruim.
- **ROAS de Equilíbrio** por família = 100 ÷ margem bruta (%), com `Painel::ItemEconomics` (custo Olist/manual, tarifa,
  frete, imposto, despesas). Sem custo, não se afirma lucro (fica "—"). Referência das fontes sem custo: 3,33.
- **Regras da casa** (declaradas na tela): 30 cliques para julgar conversão, 500 impressões para CTR; gasto relevante
  ≥ R$ 10; anúncio com menos de 30 dias e família com amostra insuficiente são **intocáveis** (não entram em sinal nem fila).
- **Sinais por família:** `saiu_do_ar_com_historico` (hold/delegated/revoked com receita), `gasto_sem_receita`,
  `impressao_sem_clique`, `abaixo_do_equilibrio` (só com receita > 0), `familia_com_multiplos_anuncios_ativos` (verba no
  pior ROAS), `capa_suspeita` (sem selo de imagem, CTR abaixo da média da conta com amostra), `idle_recomendado`,
  `exposicao_perdida_por_orcamento` (≥ 20%) e `_por_ad_rank` (≥ 50%) só quando a campanha tem uma família ativa (share
  exato); com várias famílias, esses dois viram itens no nível da campanha.
- **Fila ("O que mexer agora"):** classes em ordem: destravar receita parada → estancar desperdício → corrigir alocação
  → abrir verba onde há retorno (só com ROAS ≥ equilíbrio) → ganhar posição → ajuste fino; dentro da classe, por valor em
  jogo. Até `max_actions` (7); o resto vai para "próxima rodada"; sem valor estimável vai para "observar". Cada item: uma
  ação, evidência em números, o que checar antes (estoque, reputação, preço) e prazo de reavaliação. Fecha com a linha do
  TACOS e a direção esperada.
- **Leilão por campanha:** aparece / perde por orçamento / perde por classificação (somam 1), `acos_benchmark` contra o
  ACOS praticado, ROAS Objetivo e equilíbrio (o maior das famílias ativas).
- **Diagnóstico** (`Painel::AdsDiagnosis`, `GET /api/ads/diagnosis?family=` ou `?campaign_id=`): bloqueadores primeiro
  (fora do ar com histórico, amostra), depois a árvore por sintoma (gasta e não vende, CTR baixo, clica e não compra,
  ROAS caiu, abaixo do equilíbrio, vários ativos, possível canibalização; na campanha: perde por orçamento, perde por
  classificação, não gasta o orçamento). Devolve veredito em uma frase, evidência, descartados, o que fazer em ordem com
  prazo, o que não fazer e incerteza.
- **Decisões** (`ml_ad_decisions`, `POST /api/ads/decisions`, `DELETE /api/ads/decisions/:id`, só administradores): cada
  item da fila pode ser marcado como feito ou ignorado; o "antes" é gravado na hora e o "depois" (7 dias fechados
  seguintes, parcial até completar) aparece no bloco "Decisões dos últimos 30 dias". Item decidido nos últimos 7 dias
  fica marcado na fila.
- **Estrutura de campanhas** (`Painel::AdsStructure`, bloco "Estrutura de campanhas", chave `structure` da análise; só
  recomendação, a execução é no Seller Center). Sugestões, cada uma com campanha de origem/destino, orçamento diário,
  ROAS Objetivo sugerido, valor em jogo, racional em números, efeito esperado (declarado como estimativa) e o que checar:
  - `dividir`: campanha ativa com ≥ 3 famílias, gasto relevante e leilão consistente perdendo ≥ 50% por classificação ou
    ≥ 20% por orçamento, em que uma família concentra ≥ 25% da verba, rende ≥ o seu equilíbrio e tem amostra de conversão
    → campanha exclusiva (share exato, orçamento e ROAS Objetivo próprios), levando a parcela da verba (realocação);
  - `mover`: família com sinal `abaixo_do_equilibrio` numa campanha compartilhada cujo ROAS Objetivo não é de
    rentabilidade para ela (< 1,5× o equilíbrio) → campanha de rentabilidade com ROAS Objetivo ≥ 1,5× o equilíbrio (mín. 6);
  - `ativar`: anúncio fora de campanha (`idle`) com margem positiva, estoque e (≥ 3 vendas orgânicas em 30 dias ou
    recomendado pelo ML) → campanha ativa do mesmo `domain_id` que rende ≥ o equilíbrio dele, senão exclusiva; orçamento
    = receita diária orgânica × TACOS 3,5% (mín. R$ 1); valor = +27% das vendas em 7 dias (média citada pela plataforma);
  - `reativar`: anúncio pausado na publicidade cujo ROAS dos 90 dias (`metrics["90d"]`) ≥ equilíbrio, com estoque →
    volta na campanha atual com a média diária de gasto dos 90 dias (mín. R$ 2);
  - `reduzir`: só quando o plano estoura o teto: campanha ativa com ROAS abaixo do equilíbrio cede verba (metade do
    orçamento se o ROAS é menor que metade do equilíbrio, senão só o necessário).
  ROAS Objetivo sugerido: crescimento = 1,2× o equilíbrio (mín. 3,3); rentabilidade = 1,5× (mín. 6); ambos entre 1 e 35.
  **Limite diário** (`companies.ads_daily_budget_max`, Configurações → Ads): soma dos orçamentos diários das
  campanhas ativas + dinheiro novo (ativar/reativar, por valor em jogo) nunca passa do teto; `dividir`/`mover` só realocam.
  O que não cabe fica `within_limit: false` com nota; se uma redução libera verba, passa a caber "só com a redução". Sem
  limite informado, o plano avisa (`plan.note`) e não aplica teto.

## Dados e atualização
- **Leilão por campanha** (`ml_ad_campaigns.auction`, lido no detalhe de cada campanha a cada sync completa): impression
  share, perdas por orçamento e por classificação, `acos_benchmark`, custo e receita, nas janelas `7d` (últimos 7 dias
  fechados), `7d_prev` (os 7 anteriores) e `30d`; `consistent` confere que os três shares somam 1. Só esse endpoint traz
  essas métricas (em `ads/search` dá 400).
- **Anúncios:** `family_id`/`family_name` (produto do ML), `image_quality` e `domain_id`, que a API devolve sem documentar.
  A unidade da análise de Ads é a família, não o anúncio.
- Fonte: API de publicidade do Mercado Livre (`/advertising/...`, somente leitura, `api-version` 1 e 2). A conta de
  anunciante vem de `/advertising/advertisers?product_id=PADS`.
- `Ml::Sync::Ads` lê campanhas (`campaigns/search`), a série diária de cada campanha (`ads/search` com
  `aggregation_type=DAILY` filtrado por campanha) e os anúncios em campanha com as métricas de 7, 30 e 90 dias. Leva
  cerca de 15 segundos e cerca de 25 chamadas.
- Leitura completa **a cada 3 horas** dentro da sincronização normal (`ml_accounts.ads_synced_at`); entre elas, uma
  leitura rápida de ontem e hoje a cada 30 minutos (`ads_recent_synced_at`, `Ml::Sync::Ads.refresh_recent`). Para
  administradores também há o botão "Atualizar do Mercado Livre agora" (`POST /api/ads/sync`, `Ml::AdsSyncJob`).
- Tabelas: `ml_ad_campaigns`, `ml_ad_items` (métricas por janela em `metrics`) e `ml_ad_daily_metrics`.
- **Gasto por anúncio e por dia** (`ml_ad_item_dailies`, usado no custo de Ads de cada venda): lido dia a dia com
  `ads/search` (de = até = o dia). Cada leitura relê os últimos 3 dias e baixa até 8 dias antigos que faltam;
  `ml_ad_day_syncs` guarda quando cada dia foi lido (dia lido depois de acabar = fechado). O botão de atualizar baixa
  todos os dias que faltam de uma vez (cerca de 3 segundos por dia). Dia lido logo depois de fechar cuja soma por
  anúncio não bate com o gasto das campanhas é relido uma vez (2 por rodada, `mismatched_item_days`); diferença que
  continua é do próprio ML e entra como "Ads sem venda" em Vendas, para o total das duas seções bater.
- Anúncio que sai das campanhas é removido na leitura seguinte; anúncio cuja campanha não aparece mais mostra "Campanha encerrada".

## Arquivos
**Front (`lunna-web-radar`)**
- `app/pages/ads.vue`, `app/components/ads/` (`AdsSummary`, `CampaignsTable`, `AdsItemsTable`)
- `app/composables/useAds.ts`, `app/lib/adsClient.ts`, `app/types/ads.ts`

**API (`lunna-api`)**
- `app/controllers/ads_controller.rb` (`GET /api/ads`, `GET /api/ads/items`, `POST /api/ads/sync`)
- `app/services/painel/ads_query.rb`; `app/services/ml/sync/ads.rb`; `app/jobs/ml/ads_sync_job.rb`; métodos `ads_*` em `app/services/ml/client.rb`
- Modelos `ml_ad_campaign`, `ml_ad_item`, `ml_ad_daily_metric`; migration `20261018100001_create_ml_ads.rb`

## Pendências
- Só leitura: o Lunna não altera campanhas, orçamentos nem metas no Mercado Livre.
- Não cruza o investimento com o lucro líquido do anúncio (margem depois de Ads) nem mostra Brand Ads/Display.
- A coluna de desempenho por palavra-chave não existe na API de Product Ads.

- Períodos: Hoje, Ontem, 7 dias, Mês até hoje (`mtd`, do dia 1º até hoje), 30 dias, 60 dias, 3 meses ou datas escolhidas.
