---
name: secao-financeiro
description: Use ao alterar a seção Financeiro do Lunna (DRE do período x anterior, indicadores de saúde, gráficos, extrato do ML, conciliação e a aba Repasses com o Mercado Pago).
---

1. Leia `docs/secoes/financeiro.md` (e `vendas.md`: a conta por venda é a mesma).
2. Código: `app/services/painel/finance_query.rb` (tudo é calculado aqui), `Painel::SalesQuery#period_rows` (vendas de uma janela, inclusive o período anterior), `Painel::ReturnsQuery` (devoluções), `ml_billing_charges` (extrato do ML, `Ml::Sync::BillingCharges`); front `app/pages/financeiro.vue`, `components/financeiro/`.
3. Regras: o período anterior tem sempre o mesmo tamanho (mês fechado compara com o mês anterior inteiro; mês em andamento, com os mesmos dias do mês anterior); lançamentos manuais (`finance_entries`) entram no DRE; linhas de tarifa/frete/Ads têm duas bases (`basis=lunna|extrato`); taxa de parcelamento (`CFONPN`) é neutra; bonificação de venda cancelada não é crédito. Nova cobrança do ML com código novo cai em "Outras": classifique em `FinanceQuery::GROUPS` se for de venda, envio, devolução, Ads ou Full.
4. Repasses (Mercado Pago): `Painel::RepassesQuery` cruza previsto x faturado x pagamento (`mp_payments`) x crédito na conta (`mp_release_lines`), por envio. Taxas do MP: tarifa = `ml_sale_fee` + `mp_processing_fee` + `mp_financing_*`; `financing_fee` é do comprador; `coupon_fee` é a parte do vendedor no cupom. O frete pago pelo comprador é outro pagamento (`marketplace_shipment`, `order_id` = envio). Relatório de liberações é semanal (segunda). Nova `description` no relatório: rótulo em `MpReleaseLine::LABELS`.
5. Somente leitura: a seção não escreve no ML nem altera Vendas; divergências aparecem na conciliação.
6. Mudou regra ou arquivo? Atualize `docs/secoes/financeiro.md` no mesmo commit e rode `RAILS_ENV=test` em `spec/requests/finance_spec.rb` e `spec/services/mp/sync_spec.rb`.
6. Linha Cupons (parte do vendedor) no DRE/Despesas e previsto dos Repasses já descontando o cupom.
- Despesas fixas mensais (11/11/2026): `/financeiro/despesas-fixas`, `FixedExpense`, `Painel::FixedExpenseRate`; mês fechado com lançamento usa total ÷ faturamento nas vendas e no DRE; mês corrente e mês sem lançamento usam `companies.fixed_expenses_pct`.
