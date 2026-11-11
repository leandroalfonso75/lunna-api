# Financeiro

Seção criada em 05/11/2026 a pedido do usuário: a saúde financeira da operação no Mercado Livre, organizada como um
**demonstrativo de resultado (DRE)** do período escolhido, sempre comparado com o **período imediatamente anterior de
mesmo tamanho** (hoje x ontem; 30 dias x os 30 anteriores; setembro x agosto). Tudo é calculado na API
(`Painel::FinanceQuery`); o front só exibe.

## O que mostra
- **Quatro abas**: as três abaixo (pedido do usuário em 05/11/2026) e **Repasses** (06/11/2026, seção própria abaixo).
- **Três abas** (pedido do usuário em 05/11/2026), com os mesmos filtros no topo e abrindo no **mês atual**:
  **Visão geral e DRE** (indicadores, saúde, gráficos e o demonstrativo), **Receita** (totais, receita por dia e por
  semana x período anterior, com Ads x orgânica, por logística, produtos que mais faturam, e os lançamentos de outras
  receitas) e **Despesas** (cada despesa com o período anterior e % da receita, extrato do ML por grupo, conciliação e
  os lançamentos de outras despesas).
- **Lançamentos manuais** (`finance_entries`, `FinanceEntriesController`, `GET/POST/PATCH/DELETE /api/finance/entries`;
  escrita só admin): outra receita (rendimentos, venda fora do ML, crédito) ou outra despesa (embalagens, pessoal,
  contador, software, marketing fora do ML, logística própria, perda). Entram no DRE como "(+) Outras receitas
  (lançadas)" e "(−) Outras despesas (lançadas)", antes do lucro antes de Ads.
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
- **Conciliação Lunna x extrato** (refeita em 06/11/2026 pelas **mesmas vendas e envios**): tarifas de venda e fretes
  comparam o calculado x o cobrado para as vendas/envios do período; o que ainda não foi cobrado fica fora e aparece
  como "pendente"; "diferente" conta os que o ML cobrou com outro valor; "calendário" é o total do extrato pela data da
  cobrança (mistura outros períodos e canceladas, por isso dava +7% / +12% até 05/11). Ads compara o gasto por dia com
  a tarifa `PADS` deslocada em um dia (o ML lança no dia seguinte). Fretes de devolução: custo por reclamação x tarifas
  cobradas no período. Achado da investigação de 06/11: as tarifas de venda
  batem venda a venda (1.335 de 1.344). No frete, quando o **comprador paga parte do frete** (venda sem frete grátis),
  o ML cobra do vendedor a **etiqueta cheia** (`list_cost`) e a parte do comprador entra no pagamento da venda:
  cobrado = previsto + parte do comprador em 217 de 217 casos (60 dias). Não é cobrança a maior. Por isso a conciliação
  de fretes compara cobrado x (previsto + parte do comprador), lista os envios fora dessa conta (`divergent`) e a base
  "Extrato" desconta o frete pago pelos compradores. O custo da venda em Vendas segue o previsto (líquido);
  `shipping.seller_cost_billed` traz o cobrado, só para conferência.
- Exportação do DRE em CSV. Rodapé com a cobertura dos dados (vendas desde 11/06/2026; extrato desde o início do
  período de faturamento guardado).

## Aba Repasses: conciliação com o Mercado Pago (06/11/2026)
Pedido do usuário: cruzar o valor previsto da venda, o faturado pelo ML e o que de fato foi descontado e creditado na
conta do Mercado Pago. Carrega à parte (`GET /api/finance/repasses`, `Painel::RepassesQuery`), com os mesmos filtros.
- **Fontes** (o token do ML já lê a API do Mercado Pago; nada é escrito):
  - `mp_payments` (`Mp::Sync::Payments`, `/v1/payments/search` por data de atualização): cada pagamento com as taxas
    de `charges_details` separadas e o líquido (`net_received_amount`). A busca do MP não mantém a ordem entre
    páginas, então o import lê **janelas de 3 dias inteiras** (80 páginas por rodada; o resto segue na próxima).
  - `mp_release_lines` (`Mp::Sync::ReleaseReports`, `/v1/account/release_report`): o extrato da conta (cada crédito,
    débito e o saldo). O MP gera o relatório **toda segunda-feira** com a semana anterior; a semana corrente aparece
    como "Liberado, aguardando relatório". CSV com `;` lido por split (o `CSV` do Ruby recusa as aspas do arquivo);
    cada linha gravada uma vez (`line_key`), mesmo que venha em dois relatórios.
  - As duas rodam na rodada diária (`Ml::Sync::Run#sync_mercado_pago`); uma falha vira nota e não derruba a rodada.
    Histórico carregado: 120 dias (pagamentos desde 04/06/2026, movimentos desde 06/07/2026).
- **Quatro pernas por venda** (agrupada por envio, porque o carrinho tem uma etiqueta): 1) previsto no Lunna =
  receita − tarifa − frete do vendedor; 2) faturado pelo ML (`ml_billing_charges`); 3) líquido do pagamento no MP,
  somando o pagamento do frete pago pelo comprador (`description = marketplace_shipment`, com `order_id` = id do
  envio); 4) creditado na conta (linhas `payment`/`shipping` do relatório com `source_id` = pagamento).
- **Composição das taxas no MP**: tarifa do Lunna = `ml_sale_fee` + `mp_processing_fee` + `mp_financing_*`;
  `financing_fee` é o juro do parcelamento pago pelo comprador (`financing_transfer`) e fica de fora; frete = `shp_*`
  (etiqueta cheia); `coupon_fee` (de `collector`) = participação do vendedor no cupom, **custo que o Lunna não contava**.
- **Situações**: Conferido; Conferido (frete descontado na liberação: carrinho com frete na fatura, o pagamento não
  desconta a etiqueta e a liberação sim); Cupom com participação do vendedor; Frete previsto que o ML não cobrou; Em
  mediação; Reembolsada/cancelada; Pagamento não localizado; Diferença a verificar. Crédito: Creditado, A liberar (data
  de liberação futura), Liberado aguardando relatório, Não localizado no extrato, Sem crédito. Tolerância R$ 0,05.
- **Descontos nas três fontes**: tarifa, frete, cupom e líquido em Lunna x faturado x MP, só nas vendas pagas e já
  faturadas (o mesmo conjunto nas três colunas).
- **Movimentos da conta** no período (pela data do movimento), por tipo (`MpReleaseLine::LABELS`), com o período
  anterior, saldo no início e no fim e as reservas ainda retidas (soma negativa de `reserve_for_*` desde o início dos dados).
- Resultado de outubro/2026: 1.262 de 1.266 vendas explicadas; R$ 384 de cupom do vendedor em 98 vendas.

## Regras e fontes
- Vendas e custos por venda: `Painel::SalesQuery#period_rows` (mesma conta de Vendas: receita − custo − tarifa − frete −
  despesas fixas − imposto; Ads rateado por anúncio no período). Período anterior: `window` com `@window_override`.
- Ads do período: `ml_ad_daily_metrics.cost` por dia (soma das campanhas).
- Devoluções: `Painel::ReturnsQuery` com `from/to` do período (pela abertura da reclamação).
- Extrato: `ml_billing_charges` (`Ml::Sync::BillingCharges`, ver reclamacoes.md), grupos em `FinanceQuery::GROUPS`
  (bonificação = código da cobrança com B no lugar do C; `BPAD` é a de Ads).
- Período anterior: mês **fechado** = o mês anterior inteiro; mês **em andamento** (mês atual ou "mês até hoje") = os
  mesmos dias do mês anterior (05/11 → 01 a 05/10; pedido do usuário em 05/11/2026); o restante = mesmo número de dias
  logo antes. Quando o anterior começa antes da venda mais antiga guardada, a tela avisa "comparação parcial".
- Limites: vendas guardadas por 3 meses (desde 11/06/2026); extrato desde fevereiro/2026 (período aberto e anterior).

## Arquivos
- API: `app/services/painel/finance_query.rb`, `app/controllers/finance_controller.rb`, rota `GET /api/finance`;
  teste `spec/requests/finance_spec.rb`.
- Front (`lunna-web-radar`): `app/pages/financeiro.vue`, `app/components/financeiro/FinanceDailyChart.vue`,
  `FinanceEntriesPanel.vue`, `app/types/finance.ts`; item "Financeiro" no menu, depois de Curva ABC.
- Lançamentos: `app/models/finance_entry.rb`, `app/controllers/finance_entries_controller.rb`.
- Repasses: `app/services/painel/repasses_query.rb`, `FinanceQuery.repasses`, rota `GET /api/finance/repasses`;
  `app/services/mp/client.rb`, `app/services/mp/sync/payments.rb`, `app/services/mp/sync/release_reports.rb`;
  modelos `MpPayment`, `MpReleaseLine`; migração `20261106030001`; testes `spec/services/mp/sync_spec.rb` e o exemplo de
  repasses em `spec/requests/finance_spec.rb`. Front: `app/components/financeiro/FinanceRepassesTab.vue`.

## Próximos passos (a definir com o usuário)
- Metas por indicador (hoje só a margem mínima vem da empresa; TACOS, custo do ML e devoluções usam referências fixas).
- Guardar o extrato de mais períodos (hoje: aberto e anterior) para fechar meses mais antigos.
- Levar o cupom com participação do vendedor (`mp_payments.coupon_amount`) para o custo da venda em Vendas e no DRE.
- Pedir ao MP um relatório de liberações sob demanda (POST) para fechar a semana corrente sem esperar a segunda-feira.

## Atualizações de 06–07/11/2026

- **Cupons:** linha "(−) Cupons (parte do vendedor)" no DRE e em Despesas (descontada no pagamento do Mercado Pago; não
  aparece no extrato do ML). Nos Repasses, o previsto já desconta o cupom.
- **Repasses:** pagamentos e liberações do Mercado Pago desde 04–05/2026 (histórico importado em 06/11).

## Despesas fixas mensais (11/11/2026)

- **Tela:** Financeiro › Despesas › botão "Incluir Despesas" abre `/financeiro/despesas-fixas`: escolhe o mês, lança as
  despesas fixas (aluguel, salários, FGTS, INSS, bonificações, transporte, material de expediente...; categorias em
  `FixedExpense::CATEGORIES`), lista relida a cada inclusão, alterar/excluir, "Copiar do mês anterior" quando o mês está
  vazio. No fim, o comparativo **Faturamento x Despesas Fixas** com o percentual e a lista dos meses lançados.
- **Regra** (`Painel::FixedExpenseRate`): mês **fechado** com despesas lançadas e faturamento → percentual = total das
  despesas fixas do mês ÷ faturamento do mês, e ele substitui o padrão em **todas as vendas daquele mês** (Vendas:
  despesas fixas e lucro; DRE: linha "Despesas fixas"). **Mês corrente**, mês sem lançamento ou sem faturamento → o
  padrão de Configurações › Empresa (`companies.fixed_expenses_pct`). Nada é gravado na venda: a conta é refeita na
  leitura, então lançar, alterar ou excluir recalcula na hora.
- **Faturamento do mês:** receita das vendas não canceladas de todas as contas da empresa (preço × quantidade, data da
  venda em São Paulo), igual ao total de Vendas do mês.
- **Fora da regra:** Anúncios, Curva ABC e Promoções (preço para frente) seguem no padrão da empresa.
- **API:** `GET/POST /api/finance/fixed_expenses`, `PATCH/DELETE /api/finance/fixed_expenses/:id`,
  `POST /api/finance/fixed_expenses/copy`; escopo da empresa; escrita só admin. Tabela `fixed_expenses`.
- **Atenção:** despesa lançada aqui não deve ser lançada de novo em "Outras despesas (lançadas)" (contaria duas vezes).
