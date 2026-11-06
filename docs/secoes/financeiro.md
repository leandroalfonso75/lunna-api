# Financeiro

Seção criada em 05/11/2026 a pedido do usuário: a saúde financeira da operação no Mercado Livre, organizada como um
**demonstrativo de resultado (DRE)** do período escolhido, sempre comparado com o **período imediatamente anterior de
mesmo tamanho** (hoje x ontem; 30 dias x os 30 anteriores; setembro x agosto). Tudo é calculado na API
(`Painel::FinanceQuery`); o front só exibe.

## O que mostra
- **Filtros, os mesmos de Vendas:** Hoje, Ontem, 7 dias, Mês até hoje, 30, 60 dias, 3 meses, mês (lista) ou datas;
  logística (Full, Flex, Coleta, Agência, Outras) e busca (produto, SKU, anúncio, comprador). Com filtro de logística
  ou busca, as despesas da conta que não são por venda (Full, outras do ML, créditos) continuam as do período inteiro,
  e a tela avisa.
- **Base das tarifas, fretes e Ads** (`basis`): **Por venda** (padrão: calculado venda a venda, pela data da venda,
  como em Vendas) ou **Extrato do ML** (o que o ML cobrou de fato no período, pela data da cobrança).
- **Indicadores** com variação sobre o período anterior (valor, diferença e %; verde = melhorou): receita bruta, lucro
  líquido pós Ads, margem líquida, margem bruta, vendas, ticket médio, TACOS (Ads ÷ receita) e custo do ML ÷ receita.
- **Saúde** (semáforo): margem líquida contra a margem mínima da empresa (Configurações › Empresa); TACOS (referência
  até 10%); custo do ML ÷ receita (até 30%); devoluções e reembolsos ÷ receita (até 5%).
- **Gráficos:** por dia, período atual x anterior alinhados pela posição (1º dia com 1º dia), em receita ou lucro pós
  Ads; e "para onde vai a receita" (composição das despesas em % da receita).
- **DRE** (cada linha com valor, % da receita, período anterior e variação; clique abre a nota e o detalhe):
  1. Receita bruta de vendas (vendas pagas; carrinho = uma venda)
  2. (−) Reembolsos a compradores (`transaction_amount_refunded` das vendas que contam na receita; cancelada já está fora)
  3. = Receita líquida
  4. (−) Custo dos produtos vendidos (Olist PEPS ou manual; venda sem custo fica de fora e a nota diz quantas)
  5. = Lucro bruto (margem bruta = lucro bruto ÷ receita líquida)
  6. (−) Tarifas de venda do ML · 7. (−) Fretes pagos pelo vendedor (base Por venda ou Extrato)
  8. (−) Impostos (% da empresa) · 9. (−) Despesas fixas (% da empresa)
  10. (−) Despesas com devoluções (card Devoluções: frete de envio retido, frete de devolução, tarifas, reembolso parcial)
  11. (−) Despesas do Full (extrato: armazenamento `CFWA`, coleta `CFCBE`, estoque antigo `CFBA`)
  12. (−) Outras cobranças do ML (extrato: Minha página `CESM`, DIFAL `CDIFAL`, não classificadas)
  13. (+) Créditos e bonificações do ML (extrato: cancelamentos de tarifa/frete de vendas que estão na receita, anulação
      de Ads e outras; bonificação de venda **cancelada** fica fora, porque a venda já não está na receita)
  14. = Lucro antes de Ads · 15. (−) Product Ads (Ads por dia ou `PADS` do extrato) · 16. = Lucro líquido pós Ads
- **Extrato do Mercado Livre no período**, por grupo (cobrado, devolvido, líquido, linhas): tarifas de venda, fretes,
  devoluções, Product Ads, taxa de parcelamento (**neutra**: o comprador paga o acréscimo e o ML repassa a mesma
  cobrança), Full e outras.
- **Conciliação Lunna x extrato:** tarifas de venda, fretes, Product Ads e fretes de devolução, com a diferença e %.
  Diferenças vêm do calendário (venda x cobrança; Ads é cobrado no dia seguinte) e de cancelamentos. Em 05/11, 30 dias:
  tarifas +7%, fretes +11,5%, Ads +0,9%.
- Exportação do DRE em CSV. Rodapé com a cobertura dos dados (vendas desde 11/06/2026; extrato desde o início do
  período de faturamento guardado).

## Regras e fontes
- Vendas e custos por venda: `Painel::SalesQuery#period_rows` (mesma conta de Vendas: receita − custo − tarifa − frete −
  despesas fixas − imposto; Ads rateado por anúncio no período). Período anterior: `window` com `@window_override`.
- Ads do período: `ml_ad_daily_metrics.cost` por dia (soma das campanhas).
- Devoluções: `Painel::ReturnsQuery` com `from/to` do período (pela abertura da reclamação).
- Extrato: `ml_billing_charges` (`Ml::Sync::BillingCharges`, ver reclamacoes.md), grupos em `FinanceQuery::GROUPS`
  (bonificação = código da cobrança com B no lugar do C; `BPAD` é a de Ads).
- Período anterior de um mês = o mês anterior inteiro; o restante = mesmo número de dias logo antes. Quando o anterior
  começa antes da venda mais antiga guardada, a tela avisa "comparação parcial".
- Limites: vendas guardadas por 3 meses (desde 11/06/2026); extrato desde fevereiro/2026 (período aberto e anterior).

## Arquivos
- API: `app/services/painel/finance_query.rb`, `app/controllers/finance_controller.rb`, rota `GET /api/finance`;
  teste `spec/requests/finance_spec.rb`.
- Front (`lunna-web-radar`): `app/pages/financeiro.vue`, `app/components/financeiro/FinanceDailyChart.vue`,
  `app/types/finance.ts`; item "Financeiro" no menu, depois de Curva ABC.

## Próximos passos (a definir com o usuário)
- Metas por indicador (hoje só a margem mínima vem da empresa; TACOS, custo do ML e devoluções usam referências fixas).
- Guardar o extrato de mais períodos (hoje: aberto e anterior) para fechar meses mais antigos.
