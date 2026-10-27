---
name: secao-vendas
description: Use ao alterar a página Vendas do Lunna (pedidos do Mercado Livre dos últimos 3 meses, envio, pagamento, lucro por venda, filtros e busca).
---

1. Leia `docs/secoes/vendas.md` (conta do lucro, privacidade, como os dados são baixados).
2. Código principal: `app/services/painel/sales_query.rb`, `sales_controller.rb`, `sale_issues.rb`, `app/services/ml/sync/orders.rb`, `shipments.rb` e `claims.rb`, `app/jobs/ml/sales_backfill_job.rb`; front `app/pages/vendas.vue` e `components/vendas/` (repositório `lunna-web-radar`).
3. Custo Ads = gasto do anúncio no período (`ml_ad_item_dailies`) ÷ unidades vendidas dele no período; o gasto de anúncios sem venda no período (mais o que o ML não detalha por anúncio) é "Ads sem venda" no resumo, para o total bater com a seção Ads; dia da venda não fechado deixa a venda "pendente". Cancelamento/reclamação/devolução: motivo em `Painel::SaleIssues` a partir de `cancel_detail` e `ml_orders.claims`; pedidos alterados (`order.date_last_updated`) são relidos e o envio é relido quando o pedido muda. Lucro pós Ads = lucro líquido − custo Ads. Frete de carrinho: vendas do mesmo envio dividem o frete do vendedor por unidade; imposto e despesas fixas são % da receita dos itens; custo vem de `Olist::UnitCost` (ver `docs/secoes/produtos.md`).
4. Respeite: Mercado Livre somente leitura; nunca gravar nome, telefone ou endereço do comprador (só cidade/UF); lucro calculado só na API.
5. Mudou regra ou arquivo? Atualize `docs/secoes/vendas.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
