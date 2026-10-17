---
name: secao-vendas
description: Use ao alterar a página Vendas do Lunna (pedidos do Mercado Livre dos últimos 3 meses, envio, pagamento, lucro por venda, filtros e busca).
---

1. Leia `docs/secoes/vendas.md` (conta do lucro, privacidade, como os dados são baixados).
2. Código principal: `app/services/painel/sales_query.rb`, `sales_controller.rb`, `app/services/ml/sync/orders.rb` e `shipments.rb`, `app/jobs/ml/sales_backfill_job.rb`; front `app/pages/vendas.vue` e `components/vendas/` (repositório `lunna-web-radar`).
3. Respeite: Mercado Livre somente leitura; nunca gravar nome, telefone ou endereço do comprador (só cidade/UF); lucro calculado só na API.
4. Mudou regra ou arquivo? Atualize `docs/secoes/vendas.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
