---
name: secao-anuncios
description: Use ao alterar a página Anúncios do Lunna (tabela de anúncios, colunas de custo/comissão/frete/imposto, lucro líquido, ordenação).
---

1. Leia `docs/secoes/anuncios.md` (conta do lucro líquido, colunas, ordenação).
2. Código principal: `app/services/painel/item_economics.rb`, `item_query.rb`, `items_controller.rb`; custo vem de `app/services/olist/unit_cost.rb`. Front: `app/pages/anuncios.vue`, `components/painel/ItemsTable.vue`.
3. Respeite: cálculo só na API; parâmetros (imposto, despesas fixas) por empresa; sem barra de rolagem horizontal.
4. A conta do lucro por venda (seção Vendas) segue a mesma ideia; se mudar custo, imposto ou despesas fixas, confira também `docs/secoes/vendas.md`.
5. Mudou regra ou arquivo? Atualize `docs/secoes/anuncios.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md), por exemplo `spec/services/painel`.
