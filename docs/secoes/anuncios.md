# Anúncios

Tabela de anúncios do Mercado Livre com o **lucro líquido por unidade**.

## O que mostra
- Abas por situação (Ativos, Pausados, Finalizados, Todos), busca e filtros por tipo e envio.
- Colunas: Anúncio, SKU, Preço, Estoque, **Custo, Comissão, Frete/taxas, Desp. fixas, Imposto, Lucro líquido (% em cima,
  R$ embaixo)**, Cobertura e Qualidade. Cobertura e Qualidade somem abaixo de 1280 px de largura (continuam no detalhe).
- A tabela não tem barra de rolagem horizontal.
- Ao clicar no anúncio abrem cards: Preço e oferta, **Desempenho 7 dias** (visitas, vendas, conversão, variação nas
  vendas, faturado, após tarifa), **Resultado por unidade**, Estoque e cadastro, Qualidade.
- Ordenação por preço, estoque, cobertura, qualidade, título, SKU e **% de lucro líquido** (as colunas de custo e
  despesas não ordenam).

## Conta do lucro líquido (por unidade vendida)
`preço de venda − custo − comissão − frete/taxas − despesas fixas − imposto`
- **Custo:** do Olist pelo SKU (`Olist::UnitCost`: PEPS → cadastro → médio; kit = soma dos componentes). Sem custo no
  Olist, usa o custo manual do SKU (`ml_costs`: custo + extra). Sem nenhum, aparece "sem custo" e o lucro não é calculado.
- **Comissão:** parte percentual da tarifa prevista no anúncio (`fee_now` menos taxa fixa e financiamento, lidos de
  `fee_details`). Sem o detalhe, a tarifa inteira entra como comissão.
- **Frete/taxas:** frete pago pelo vendedor (`ship_cost`) + taxa fixa + financiamento.
- **Despesas fixas:** % do preço, campo `companies.fixed_expenses_pct` (padrão 3%; ainda sem tela de edição).
- **Imposto:** `companies.tax_pct` (Configurações > Impostos e margem) × preço.
- Lucro em R$ e em % do preço de venda. Implementado em `Painel::ItemEconomics`.

## Arquivos
**Front (`lunna-web`)**
- `app/pages/anuncios.vue`, `app/components/painel/ItemsTable.vue`
- `app/composables/useItemsTable.ts`, `app/lib/itemsQuery.ts`, `app/lib/painelClient.ts`, `app/types/painel.ts`

**API (`lunna-api`)**
- `app/controllers/items_controller.rb` → `GET /api/items`
- `app/services/painel/`: `item_query` (filtro, busca, ordenação, paginação), `item_economics` (lucro), `item_metrics`
  (agregados), `filter_expression`, `labels`, `alerts`
- `app/services/olist/unit_cost.rb`, `kit_resolver.rb` (custo vindo do Olist)
- `app/services/ml/sync/*` (leitura do Mercado Livre; `details.rb` guarda tarifa e frete)

## Regras importantes
- Ordenar por `net_profit_pct` calcula o lucro de todos os anúncios do filtro antes de paginar; anúncios sem lucro vão
  sempre para o fim.
- A tarifa detalhada de cada anúncio é relida a cada 12 h.

## Pendências
- Poucos anúncios têm custo ainda (depende do Olist e do PEPS).
- Campo "Despesas fixas" editável em outra página.
