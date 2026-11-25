# Anúncios

Tabela de anúncios do Mercado Livre com o **lucro antes Ads por unidade**.

## O que mostra
- Abas por situação (Ativos, Pausados, Finalizados, Todos), busca e filtros por tipo e envio.
- Colunas: Anúncio, SKU, Preço, Estoque, **Custo, Comissão, Frete/taxas, Desp. Oper., Imposto, Lucro antes Ads (% em cima,
  R$ embaixo)**, Cobertura e Qualidade. Cobertura e Qualidade somem abaixo de 1280 px de largura (continuam no detalhe).
- A tabela não tem barra de rolagem horizontal.
- Ao clicar no anúncio abrem cards: Preço e oferta, **Desempenho 7 dias** (visitas, vendas, conversão, variação nas
  vendas, faturado, após tarifa), **Resultado por unidade**, Estoque e cadastro, Qualidade.
- Ordenação por preço, estoque, cobertura, qualidade, título, SKU e **% de lucro antes Ads** (as colunas de custo e
  despesas não ordenam).

## Conta do lucro antes Ads (por unidade vendida)
`preço de venda − custo − comissão − frete/taxas − despesas operacionais − imposto`
- **Custo:** do Olist pelo SKU (`Olist::UnitCost`: PEPS → cadastro → médio → custo da última entrada; kit = soma dos componentes). Sem custo no
  Olist, usa o custo manual do SKU (`ml_costs`: custo + extra). Anúncio com variações cujo SKU do anúncio não existe
  no Olist (ex.: MONDSC13-DIF, variações LS-SC13-DIF-110/220, kits do secador + LS-DIF): custo = média dos SKUs das
  variações vendidas nos últimos 90 dias, ponderada pelas unidades (`Painel::VariationCost`, fonte "variacoes"); vale
  também em Promoções e na Análise de Ads. Sem nenhum, aparece "sem custo" e o lucro não é calculado.
- **Comissão:** parte percentual da tarifa prevista no anúncio (`fee_now` menos taxa fixa e financiamento, lidos de
  `fee_details`). Sem o detalhe, a tarifa inteira entra como comissão.
- **Frete/taxas:** frete pago pelo vendedor (`ship_cost`) + taxa fixa + financiamento.
- **Despesas Operacionais:** % do preço, campo `companies.fixed_expenses_pct` (padrão 3%; ainda sem tela de edição).
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
- Anúncio sem custo é o de produto sem nenhuma entrada com valor no Olist; preencher o preço de custo no cadastro do produto
  (aba Custos) resolve na próxima leitura.
- Campo "Despesas Operacionais" editável em outra página.

## Custo de Ads e lucro pós Ads (30/10)
- **Custo Ads** por unidade = gasto do anúncio em Product Ads nos últimos N dias fechados ÷ unidades vendidas dele no
  período (vendas não canceladas), com N em Configurações → Anúncios (`companies.ads_cost_days`: 7, 15 ou 30; padrão
  15). Sem gasto, ou gasto sem venda, fica zero. Código em `Painel::AdsUnitCost` (também usado pelas Promoções).
- **Lucro pós Ads** = lucro antes Ads − custo Ads por unidade (`Painel::ItemEconomics`, `net_profit_after_ads`); ordenável.
- Na tabela, os custos (custo, comissão, frete/taxas, despesas operacionais, imposto, custo Ads) mostram o valor em R$ em
  vermelho e, abaixo, o % sobre o preço de venda; os lucros mostram R$ em cima e % embaixo.

## Aba Catálogo (08/11/2026)

`GET /api/items/catalog` (`Painel::CatalogQuery`, `CatalogTable.vue`): todos os anúncios de catálogo com **Sincronizado**
(tem `item_relations` com um tradicional, como em Promoções) ou **Não sincronizado**, **Ganhando / Compartilhando / Perdendo**
(`catalog_status` do price_to_win, lido a cada 30 min só para ativos; pausados ficam "Sem leitura"), preço para ganhar,
preço do vencedor e motivo, SKUs completos, preço e vendas 30d. Cartões do topo filtram; busca por MLB, título ou SKU.

## Curva ABC, data de criação, seleção, excluir e editar (24/11/2026, pedido do usuário)

- **Curva**: bola ao lado do anúncio, azul = A, verde = B, vermelha = C. É a mesma curva da seção Curva ABC
  (`Abc::Classifier`, faturamento de 30 dias acumulado com os cortes da empresa). "—" = fora da curva (finalizado sem venda).
- **Criado em**: `ml_items.date_created` (data de criação no ML, DD/MM/AAAA).
- **Ordenação** por curva (`sort=curve`: A→B→C; inverte para C→B→A) e por data de criação (`sort=date_created`: mais novo
  primeiro), feita na API sobre a lista inteira (`Painel::ItemQuery#sorted_by_extra`). Sem valor vai para o fim.
- **Caixa de seleção** à esquerda de cada anúncio, mais "selecionar todos da página" no cabeçalho. Com algum selecionado,
  aparece a barra com **Editar anúncios selecionados** e **Excluir anúncios selecionados**. A seleção vale para a página
  na tela: mudar de página ou de filtro tira da seleção o que saiu da tela.
- **Excluir** (só admin): janela "Confirma a exclusão do(s) anúncio(s) selecionado(s)?" com a lista e o aviso, e os botões
  Sim/Não. Sim chama `POST /api/items/bulk_delete` (`item_ids[]`, `confirm=true`, até 50), que no ML **finaliza**
  (`status=closed`) e depois **marca como excluído** (`deleted=true`), anúncio por anúncio (`Ml::ItemDeletion`). Não tem
  volta: excluído não pode ser reativado, só publicado de novo como anúncio novo. O ML pode recusar (ex.: estoque no Full,
  anúncio em revisão); o recusado não impede os outros, e a tela lista o motivo de cada um. Cada tentativa fica em
  `ml_item_edits` (kind `exclusao`). No Lunna o anúncio excluído passa a "Finalizado".
- **Editar**: só um anúncio, ou vários com o(s) mesmo(s) SKU(s). Os SKUs de cada anúncio são o do anúncio mais os das
  variações; a API confere em `GET /api/items/bulk_edit` (`Painel::BulkEditGroup`, até 20) e explica quando os SKUs não
  batem. O primeiro selecionado é o principal: os editores leem e sugerem a partir dele, e a publicação vale também para os
  outros, que vêm marcados na confirmação e podem ser desmarcados (`also_item_ids[]`).
  - **Ficha técnica**: modo completo (`all=true` em `/api/items/:id/specs`), com os campos já preenchidos (valor atual,
    "alterado" e "desfazer") e os que faltam. "Sugerir características" pela IA. Publica só o que mudou. Atributos de
    variação (cor, voltagem, GTIN) ficam de fora.
  - **Descrição**: o editor da Curva ABC, com "Sugerir descrição".
  - **Imagens**: o gerador com IA da Curva ABC (`AbcPhotoGenerator`). As fotos aprovadas vão para o principal e depois para
    os outros do mesmo SKU (`PicturePublisher` aceita esses destinos).

## Filtro "Anúncios criados há mais de" (24/11/2026, pedido do usuário)

- Acima das abas Todos e Catálogo: 30, 60, 90, 180 ou 365 dias, ou **Personalizado** (campo só de números, até 36.500
  dias). Vale para as duas abas e para as contagens (Ativos, Pausados, Finalizados, Todos e os contadores do Catálogo).
- API: `created_older_than=N` em `GET /api/items` e `GET /api/items/catalog` (`Painel::CreatedFilter`, por
  `ml_items.date_created < agora − N dias`). Vazio, zero ou não numérico = sem filtro. O modo focado (`?id=`) ignora o filtro.
