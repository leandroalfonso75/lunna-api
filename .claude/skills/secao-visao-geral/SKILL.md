---
name: secao-visao-geral
description: Use ao alterar a página Visão geral do Lunna (cartões, gráfico de 15 dias, alertas, mais vendidos, vendas recentes).
---

1. Leia `docs/secoes/visao-geral.md` e `docs/METRICS.md` (períodos no fuso de São Paulo).
2. Código principal: `app/services/painel/` (summary, kpis, daily, alerts…), `painel_controller.rb`; front `app/pages/index.vue` e `components/painel/`.
3. Respeite: cores e estados (ok/atenção/ruim) vêm prontos da API.
4. Mudou regra ou arquivo? Atualize `docs/secoes/visao-geral.md` no mesmo commit e rode `bundle exec rspec spec/services/painel`.
