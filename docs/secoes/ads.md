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
