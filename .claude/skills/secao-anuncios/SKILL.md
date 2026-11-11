---
name: secao-anuncios
description: Use ao alterar a página Anúncios do Lunna (tabela de anúncios, colunas de custo/comissão/frete/imposto, lucro líquido, ordenação).
---

1. Leia `docs/secoes/anuncios.md` (conta do lucro líquido, colunas, ordenação).
2. Código principal: `app/services/painel/item_economics.rb`, `item_query.rb`, `items_controller.rb`; custo vem de `app/services/olist/unit_cost.rb`. Front: `app/pages/anuncios.vue`, `components/painel/ItemsTable.vue`.
3. Respeite: cálculo só na API; parâmetros (imposto, despesas fixas) por empresa; sem barra de rolagem horizontal.
4. A conta do lucro por venda (seção Vendas) segue a mesma ideia; se mudar custo, imposto ou despesas fixas, confira também `docs/secoes/vendas.md`.
5. Anúncio com variações cujo SKU do anúncio não existe no Olist (ex.: MONDSC13-DIF): custo pela média dos SKUs das variações vendidas em 90 dias (`Painel::VariationCost`, fonte "variacoes"), também em Promoções e na Análise de Ads.
6. Mudou regra ou arquivo? Atualize `docs/secoes/anuncios.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md), por exemplo `spec/services/painel`.
6. Aba Catálogo: `Painel::CatalogQuery` (`GET /api/items/catalog`) e `components/painel/CatalogTable.vue`; sincronização = `item_relations`, ganhando/perdendo = `catalog_status`.
