---
name: secao-ads
description: Use ao alterar a página Ads do Lunna (campanhas e anúncios de publicidade/Product Ads do Mercado Livre, ACOS, ROAS, investimento, metas).
---

1. Leia `docs/secoes/ads.md` (contas, fontes de dados, períodos Hoje/Ontem/datas e janelas de 7/30/90 dias).
2. Código principal: `app/services/painel/ads_query.rb`, `ads_controller.rb`, `app/services/ml/sync/ads.rb`, `app/jobs/ml/ads_sync_job.rb`; front `app/pages/ads.vue` e `components/ads/` (repositório `lunna-web-radar`).
3. Dados: leitura completa a cada 3 horas, ontem e hoje a cada 30 minutos; anúncios de períodos não guardados (hoje, ontem, 60 dias, datas) são consultados na hora (`live_items`, 5 minutos de cache).
4. Respeite: Mercado Livre somente leitura (não alterar campanhas); ACOS/ROAS/CTR sempre recalculados na API, nunca somados entre campanhas; a API de publicidade limita a consulta a 90 dias.
5. Mudou regra ou arquivo? Atualize `docs/secoes/ads.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
