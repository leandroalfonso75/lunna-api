---
name: secao-financeiro
description: Use ao alterar a seção Financeiro do Lunna (DRE do período x anterior, indicadores de saúde, gráficos, extrato do ML e conciliação).
---

1. Leia `docs/secoes/financeiro.md` (e `vendas.md`: a conta por venda é a mesma).
2. Código: `app/services/painel/finance_query.rb` (tudo é calculado aqui), `Painel::SalesQuery#period_rows` (vendas de uma janela, inclusive o período anterior), `Painel::ReturnsQuery` (devoluções), `ml_billing_charges` (extrato do ML, `Ml::Sync::BillingCharges`); front `app/pages/financeiro.vue`, `components/financeiro/`.
3. Regras: o período anterior tem sempre o mesmo tamanho (mês fechado compara com o mês anterior inteiro; mês em andamento, com os mesmos dias do mês anterior); lançamentos manuais (`finance_entries`) entram no DRE; linhas de tarifa/frete/Ads têm duas bases (`basis=lunna|extrato`); taxa de parcelamento (`CFONPN`) é neutra; bonificação de venda cancelada não é crédito. Nova cobrança do ML com código novo cai em "Outras": classifique em `FinanceQuery::GROUPS` se for de venda, envio, devolução, Ads ou Full.
4. Somente leitura: a seção não escreve no ML nem altera Vendas; divergências aparecem na conciliação.
5. Mudou regra ou arquivo? Atualize `docs/secoes/financeiro.md` no mesmo commit e rode `RAILS_ENV=test` em `spec/requests/finance_spec.rb`.
