# Vendas

Todas as vendas (pedidos) do Mercado Livre dos últimos **3 meses**, com tudo o que a API entrega e o lucro líquido de cada uma.

## O que mostra
- **Período:** Hoje (padrão ao abrir), Ontem, 7 dias, 30 dias, 60 dias, 3 meses, **Mês** (lista com o mês atual
  primeiro, "até hoje", e os anteriores em ordem decrescente: 11/2026, 10/2026...; o mais antigo, cortado no limite de 92
  dias, aparece como "parcial"; `?month=2026-10` mostra do dia 1º ao último dia) ou datas escolhidas (no máximo 92 dias
  para trás). O botão "Mês até hoje" saiu em 03/11/2026: é o mês atual da lista (`mtd` continua aceito pela API).
- **Resumo:** vendas, faturamento (e ticket médio), lucro líquido (e % do faturamento), tarifas + frete, imposto + despesas
  fixas e custo dos produtos. Vendas canceladas ficam fora dos totais (só aparecem contadas).
- **Contagem de vendas:** uma venda = um carrinho do Mercado Livre (`pack_id`) quando houver, senão o pedido. Carrinho
  com dois produtos são dois pedidos no ML e uma venda no Olist e na tela de vendas do ML; o Lunna conta igual nos
  totais, no ticket médio, nas barras por dia, no gráfico da Visão geral e no card "Hoje". A lista segue por pedido;
  pedidos do mesmo carrinho ganham o selo "Mesmo pedido · 1/2" (balão com o carrinho e os outros pedidos) e um filete
  azul à esquerda (`cart` em cada linha de `GET /api/sales`, calculado sem filtros nem página). Decisão do usuário em
  01/11/2026.
- **Gráfico:** faturamento por dia, com vendas e lucro no balão.
- **Filtros:** situação da venda (todas, pagas, canceladas), situação do envio (preparando, a caminho, entregues, com
  problema), logística (Full, Flex, Coleta, Agência, outras), com contagens, e **busca** por nº da venda, produto, SKU,
  anúncio, comprador ou rastreio.
- **Coluna Envio:** situação do envio e, abaixo, o oval do logotipo do Mercado Livre (origem da venda) seguido do selo da
  forma de envio: imagem para Full e Agência (`public/logistica/` no lunna-web-radar: `ml-oval.png`, `full.png` com
  fundo transparente, `agencia.png`); Flex, Coleta e as demais ficam em texto. Pedido do usuário em 02/11/2026.
- **Tabela:** data, produto (foto, título, nº da venda e, na linha de baixo, SKU e unidades), **Cliente** (nome, CPF/CNPJ
  e cidade/UF, uma informação por linha; "Carregando…" até o faturamento ser lido), valor, tarifa, frete, custo, lucro líquido (% em cima, R$ embaixo) e envio.
  Colunas de valores: valor, tarifa, frete, imposto, despesas fixas, custo, **lucro líquido**, **Custo Ads** e **Lucro pós
  Ads** (% em cima, R$ embaixo). Resumo com os cartões "Custo com Ads" e "Lucro pós Ads". Ordena por data, valor e % de lucro. Sem barra de rolagem horizontal (tarifa, frete e custo somem em tela estreita).
- **Detalhe (clique na linha):** resultado da venda linha a linha, produtos (variação, tarifa, tipo de anúncio),
  pagamento (forma, parcelas, cupom, reembolso) e envio (situação, logística, destino cidade/UF, rastreio, frete pago pelo
  vendedor e pelo comprador, datas de cada etapa), com link para a venda no Mercado Livre.

## Conta do lucro líquido da venda
`receita dos itens − custo − tarifa de venda − frete pago pelo vendedor − despesas fixas − imposto`
- **Custo:** soma, por item, do custo do SKU × quantidade (`Olist::UnitCost`: PEPS → cadastro → médio; kit = componentes;
  senão o custo manual `ml_costs`). Sem custo em algum item, o lucro da venda não é calculado e ela é contada em
  "vendas sem custo".
- **Tarifa:** `sale_fee` de cada linha do pedido × quantidade (já inclui taxa fixa).
- **Frete do vendedor:** `senders[0].cost` de `/shipments/{id}/costs`. Enquanto o envio não foi lido, vale 0 e a tela avisa.
  **Carrinho:** vendas do mesmo carrinho (pack) viajam no mesmo envio, e o ML informa o frete do envio inteiro em cada
  uma. O Lunna divide esse frete entre as vendas do envio, proporcional às unidades de cada uma (vendas canceladas
  ficam de fora), para não contar o mesmo frete duas vezes. O detalhe mostra o frete do envio, a parte da venda e as
  outras vendas do carrinho.
- **Despesas fixas e imposto:** `companies.fixed_expenses_pct` e `tax_pct` × receita.
Implementado em `Painel::SalesQuery#economics`.

## Custo de Ads e lucro pós Ads
- **Custo Ads da venda:** o gasto de publicidade do anúncio **no período escolhido** (seção Ads, `ml_ad_item_dailies`)
  dividido entre as unidades vendidas desse anúncio no mesmo período (vendas não canceladas, sem os filtros da tela),
  vezes as unidades da venda. Assim o gasto de dias sem venda (que costuma virar venda indireta) também entra. Anúncio
  fora de Ads mostra "—" e o lucro pós Ads é o próprio lucro.
- **Ads sem venda:** o gasto de anúncios que não venderam nenhuma unidade no período, mais a diferença entre o gasto
  das campanhas e a soma por anúncio quando o ML não detalha tudo. Não vai para venda nenhuma: aparece no cartão
  "Custo com Ads" e sai do lucro pós Ads do resumo. Com isso o Custo com Ads de Vendas é igual ao total da seção Ads
  no mesmo período. Com filtro ou busca na tela, ele fica de fora (o resumo mostra só o rateado nas vendas filtradas).
- **Pendente:** o dia da venda ainda não foi lido depois de acabar (hoje, por exemplo). O valor é refeito a cada leitura de
  Ads (a cada 30 minutos os últimos 3 dias são relidos) até o dia fechar; o resumo conta as vendas pendentes.
- O detalhe da venda usa o mesmo período da lista e mostra a conta: gasto do anúncio no período ÷ unidades vendidas no
  período.
- Dia lido logo depois de fechar cuja soma por anúncio não bate com o gasto das campanhas é relido uma vez
  (`Ml::Sync::Ads.mismatched_item_days`).

## Cancelamento, reclamação e devolução
- **Motivo na lista e no detalhe:** venda cancelada mostra o tipo de cancelamento (`cancel_detail` do pedido: comprador
  cancelou antes do envio, cancelada por reclamação, envio não entregue, sem estoque, fraude…) e quem pediu. Reclamações
  (`payload.mediations`) são lidas em `/post-purchase/v1/claims/{id}` com o motivo em texto
  (`/claims/reasons/{id}`, ex.: "Me arrependi da compra"), o resultado (a favor de quem, com cobertura do ML) e a
  devolução (`/post-purchase/v2/claims/{id}/returns`: status e dinheiro retido/reembolsado). Ficam em `ml_orders.claims`
  (`Ml::Sync::Claims`, 40 por rodada) e em texto em `Painel::SaleIssues`. Vale também para venda paga com reclamação.
- **Releitura:** além dos pedidos criados nos últimos 4 dias, cada rodada busca os pedidos **alterados** nos últimos 2 dias
  (`order.date_last_updated.from`), para pegar cancelamento e devolução de vendas antigas. Envio é relido sempre que o
  pedido muda depois da última leitura do envio (mesmo já entregue/cancelado). Reclamação é relida quando o pedido muda
  ou a cada 2 horas enquanto estiver aberta.

## Dados e atualização
- Fonte: API do Mercado Livre, somente leitura. Pedido completo em `ml_orders.payload`; linhas em `ml_order_items`
  (com título, SKU, tipo de anúncio e variação); envio em `ml_orders.shipment`; reclamações em `ml_orders.claims`.
- **Privacidade:** do comprador guardamos id, apelido e, desde 03/11/2026 (pedido do usuário, coluna "Cliente"), nome,
  tipo e número do documento (CPF/CNPJ) e cidade/UF, lidos de `/orders/{id}/billing_info` (`Ml::Sync::BillingInfo`,
  150 pedidos por rodada, mais novos primeiro; colunas `ml_orders.buyer_*` e `billing_synced_at`). Rua, número,
  bairro, CEP e telefone continuam fora; o envio segue salvo sem nome, telefone e endereço. Na tela, CPF inteiro só
  para administrador (os demais veem `***.456.789-**`); CNPJ aparece inteiro. São dados pessoais (LGPD): usar só para a
  operação das vendas.
- A sincronização normal (5 min) relê os pedidos criados nos últimos 4 dias e os alterados nos últimos 2 dias, busca o
  envio de 60 pedidos por rodada (`Ml::Sync::Shipments`; envio em andamento é relido depois de 2 h; envio já
  entregue/cancelado só é relido se o pedido mudar depois) e as reclamações de 40 (`Ml::Sync::Claims`).
- A primeira carga de uma conta nova busca 95 dias de pedidos. O botão "Baixar os 3 meses de novo" (administrador,
  `POST /api/sales/sync`) roda `Ml::SalesBackfillJob`, que baixa os pedidos e os envios em pedaços de 100 até acabar
  (cerca de 2 envios por segundo).
- Limite do ML: a busca de pedidos pagina até 10 mil por janela; se uma conta passar disso, quebrar em janelas.

## Arquivos
**Front (`lunna-web-radar`)**
- `app/pages/vendas.vue`, `app/components/vendas/` (`SalesSummary`, `SaleDetailPanel`)
- `app/composables/useSales.ts`, `app/lib/salesClient.ts`, `app/types/sales.ts`

**API (`lunna-api`)**
- `app/controllers/sales_controller.rb` (`GET /api/sales`, `GET /api/sales/:id`, `POST /api/sales/sync`)
- `app/services/painel/sales_query.rb` (filtros, ordenação, totais, lucro, custo de Ads), `sale_issues.rb` (motivo do
  cancelamento/reclamação/devolução em texto)
- `app/services/ml/sync/orders.rb`, `shipments.rb`, `claims.rb`; `app/jobs/ml/sales_backfill_job.rb`; cliente em `app/services/ml/client.rb`
- Migrations `20261017200001_add_sale_details_to_ml_orders.rb`, `20261027010001_add_claims_to_ml_orders.rb`

## Pendências
- A comissão e a tarifa fixa aparecem somadas (`sale_fee`); separar exigiria `/orders/{id}` + `/payments`.
- Venda com reembolso parcial (`partially_refunded`) ainda conta a receita inteira.
- Sem exportação para planilha.
- Despesas fixas (3%) ainda sem campo de edição em Configurações.
- Vendas sem SKU no anúncio do Mercado Livre ficam sem custo; preencher o SKU no anúncio resolve.
- Custo Ads é um rateio pelo período: o Mercado Livre não informa qual venda veio de qual clique.
- Formato (30/10): valores em R$; sob cada custo (tarifa, frete, imposto, despesas fixas, custo Ads) o % sobre a receita da
  venda (R$ em vermelho, % em preto); lucro líquido e lucro pós Ads com R$ em cima e % embaixo.

## Frete do vendedor pelo extrato (06/11/2026)
O frete de cada venda vem de `/shipments/{id}/costs` (custo previsto para o vendedor). Quando o extrato de faturamento
do ML (`ml_billing_charges`, seção Financeiro) já tem a cobrança do envio (tarifas de envio menos cancelamentos), esse
valor cobrado passa a ser o frete da venda (`shipping.seller_cost`, `cost_source: "extrato"`; o previsto fica em
`seller_cost_estimated`). Motivo: em ~12% dos envios o ML cobra o valor cheio da etiqueta, maior que o previsto.
