---
name: secao-radar-ml
description: Use ao alterar a página Radar Mercado Livre do Lunna (filtros, categorias, histórico de pesquisas, pedidos de coleta).
---

1. Leia `docs/secoes/radar-ml.md`.
2. Código principal: front `app/lib/radar.ts`, `app/pages/radar-ml.vue`, `public/radar/` (repositório `lunna-web-radar`); API `radar_collections_controller.rb`, `radar_searches_controller.rb`.
3. Respeite: a coleta acontece só por pedido do usuário, nada agendado; a forma de coletar ainda será definida depois do deploy; o botão Pesquisar exige categoria.
4. Mudou regra ou arquivo? Atualize `docs/secoes/radar-ml.md` no mesmo commit e rode os testes dos dois lados.
