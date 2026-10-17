# Visão geral

Primeira tela do painel: resumo da conta do Mercado Livre selecionada.

## O que mostra
- Cartões com os números principais (vendas e faturamento de hoje e dos últimos 7 dias, visitas, conversão, estoque em
  risco etc.), com a comparação com o período anterior.
- Gráfico dos últimos 15 dias.
- Alertas (o que precisa de atenção hoje), mais vendidos e vendas recentes.
- Selo de sincronização (quando foi a última leitura do Mercado Livre).

## Dados
`GET /api/painel?account_id=...` (somente leitura). Tudo calculado na API a partir de `item_metrics`, `ml_orders` e
`ml_items`, atualizados a cada sincronização do Mercado Livre (5 min).

## Arquivos
**Front (`lunna-web`)**
- `app/pages/index.vue`, `app/composables/usePainel.ts`, `app/lib/painelClient.ts`
- `app/components/painel/` → `KpiCards`, `DailyChart`, `AlertsList`, `TopSellersList`, `RecentSalesList`, `PageHeader`

**API (`lunna-api`)**
- `app/controllers/painel_controller.rb`
- `app/services/painel/` → `summary`, `kpis`, `daily`, `alerts`, `top_sellers`, `recent_sales`, `sync_status`,
  `periods`, `item_metrics` (agregação por anúncio)

## Regras importantes
- Períodos fechados no fuso de São Paulo (ver [METRICS.md](../METRICS.md)).
- Alerta e estados de cor (ok/atenção/ruim) vêm prontos da API.

## Pendências
Nenhuma conhecida.
