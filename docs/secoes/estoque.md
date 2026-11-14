# Estoque

Seção criada em 14/11/2026 a pedido do usuário, logo abaixo de Produtos no menu. Duas abas, tudo calculado na API
(`Painel::StockQuery`, `StockController`); somente leitura.

## Full e reposição (aba padrão)
- Fonte: API "Planejamento de reposição para Fulfillment" do ML (documentação de 11/11/2026):
  `GET /marketplace/fbm/sellers/{seller_id}/user-products/replenishment?country=BR` (20 por página, sem `limit`).
  Lida a cada 6 horas (`Ml::FullReplenishmentJob`, `Ml::Sync::FullReplenishment`) e guardada em `ml_full_replenishments`
  (um registro por User Product). "Reler do Mercado Livre" (`POST /api/stock/full/sync`, admin) pede na hora.
- Por produto: estoque no Full, urgência do ML (Urgente, Esta semana, Próxima semana, Sem urgência), recomendação (repor ou
  não), quantidade sugerida e prazo, frequência de reposição, vendas de 30 dias, histórico de 6 semanas (unidades e dias
  sem estoque), selos (produto estrela, restrição no Full) e benefícios.
- Cruzamento com o Olist (pelo SKU): "No depósito" (disponível; kit = quantos kits os componentes montam, `KitResolver`),
  "Enviar já" = min(sugerido, disponível) e "Comprar" = sugerido − enviar já.
- Receita perdida (estimativa): vendas por dia com estoque (unidades das 6 semanas ÷ dias com estoque) × dias sem estoque ×
  preço do anúncio.
- Filtros: Repor (padrão), Urgente, Falta comprar, Sem necessidade, Todos no Full, Todos os produtos; busca por SKU, produto ou
  MLB. Ordem: repor primeiro, por urgência e quantidade.

## Depósito (ERP)
- Produtos do Olist com SKU (sem kits, que não têm estoque próprio, sem pais de variação e sem excluídos): disponível,
  reservado, Full, custo unitário (PEPS ou custo do cadastro), valor (depósito + Full), vendas de 30 dias no ML e cobertura
  em dias = (depósito + Full) ÷ venda por dia.
- **Kits contam para os componentes:** a venda e o estoque Full de um kit (ex.: secador + difusor) entram em cada componente,
  na quantidade do kit.
- Situação: OK, Cobertura baixa (< 15 dias), Sem estoque, Parado (com estoque e sem venda em 30 dias); "Full pede N un." quando
  há recomendação de reposição para o SKU.
- Filtros e ordenação: valor em estoque (padrão), menor cobertura, mais vendidos, SKU.

## Correção junto (14/11/2026)
- O estoque Full lido de `/inventories/{id}/stock/fulfillment` vinha zerado: a API responde `available_quantity` /
  `not_available_quantity` e a sincronização lia `available_units`. Corrigido em `Ml::Sync::FullStock` (afetava também a
  coluna Full da seção Produtos).

## Arquivos
- API: `app/services/painel/stock_query.rb`, `app/controllers/stock_controller.rb`, `app/services/ml/sync/full_replenishment.rb`,
  `app/jobs/ml/full_replenishment_job.rb`, `app/models/ml_full_replenishment.rb`, `spec/requests/stock_spec.rb`.
- Front: `app/pages/estoque.vue`, `app/types/stock.ts`, menu em `app/layouts/default.vue`.

## Filtro do Depósito (14/11/2026)

- Campo acima da lista: SKU, número do anúncio (MLB), título do anúncio ou palavra do nome do produto (várias palavras:
  todas precisam aparecer; sem acento). O anúncio de um kit acha os componentes. Os anúncios de cada SKU vêm do SKU do
  anúncio, das variações e das vendas dos últimos 95 dias (`listings_by_sku`).

## Anúncios do formato antigo no Full (14/11/2026)

- A API de reposição só lista User Products. Anúncio antigo com variações (ex.: MLB2729901870, SKUs LS-SC13-DIF-110/220)
  ficava fora. Agora cada estoque Full que não veio na lista vira uma linha (`source: "legacy"`, `user_product_id` =
  `INV:<inventory_id>`), com o anúncio, a variação (`GET /items/{id}`), o SKU da variação (o vendido nela ou SELLER_SKU),
  o estoque Full, as vendas de 30 dias e a cobertura em dias; sem recomendação do ML ("sem recomendação do ML · cobre N
  dias"). Hoje são 4 estoques (MLB2729901870 127V/220V e MLB1858068900 127V/220V).

- **Custo PEPS com o Full dos kits** (14/11/2026): o estoque Full de um kit conta como estoque dos componentes no PEPS
  (`Olist::SyncCosts#current_stock`), e o Full de um SKU também é achado pela lista de reposição (`Olist::FullStock`, SKU
  do Olist diferente do SKU do anúncio). Ex.: LS-SC13-110 = 911 no depósito + 343 no Full dentro do kit LS-SC13-DIF-110;
  o custo passou de R$ 85,75 para R$ 78,00 (ainda há saldo da entrada de 04/08/2026).
