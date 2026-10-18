---
name: secao-ads
description: Use ao alterar a página Ads do Lunna (campanhas e anúncios de publicidade/Product Ads do Mercado Livre, ACOS, ROAS, investimento, metas).
---

1. Leia `docs/secoes/ads.md` (contas, fontes de dados, janelas de 7/30/90 dias).
2. Código principal: `app/services/painel/ads_query.rb`, `ads_controller.rb`, `app/services/ml/sync/ads.rb`, `app/jobs/ml/ads_sync_job.rb`; front `app/pages/ads.vue` e `components/ads/` (repositório `lunna-web-radar`).
3. Respeite: Mercado Livre somente leitura (não alterar campanhas); ACOS/ROAS/CTR sempre recalculados na API, nunca somados entre campanhas; a API de publicidade limita a consulta a 90 dias.
4. Mudou regra ou arquivo? Atualize `docs/secoes/ads.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
