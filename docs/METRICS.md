# Contrato compartilhado: métricas por anúncio e rotas de leitura

## Tabela `item_metrics` (criada pelo A4; lida pelo A4 e pelo A5 — NÃO mude nomes)
Uma linha por anúncio da conta, recalculada por `Painel::ItemMetrics.refresh(account, today: Date.current)` ao fim de cada sincronização e ao salvar os parâmetros da empresa. Percentuais em 0–100. Janelas da SPEC 6 (dias fechados no fuso de São Paulo, D = hoje).

| Coluna | Tipo | Definição |
|---|---|---|
| item_id | string PK | = ml_items.item_id |
| ml_account_id | uuid FK ml_accounts (cascade), índice | |
| title | string, `collation: "pt-BR-x-icu"` | |
| status | string | status do ML |
| sku | string | nil = sem SKU |
| listing_type | string | "P" (gold_pro), "C" (gold_special) ou nil |
| full | boolean | logistic_type == "fulfillment" |
| free_shipping, catalog | boolean | |
| variations | integer | variations_count |
| price | decimal(12,2) | preço de venda (SPEC 6): `sale_price` se existir e diferente de `price`; senão `price` |
| original_price | decimal(12,2) | "de": `original_price` do item; senão `regular_price` quando `price` (venda) < `regular_price`; senão nil |
| stock | integer | available_quantity |
| quality_score | integer | |
| visits_7d, prev_visits_7d, visits_30d, prev_visits_30d | integer (0 quando sem dado) | v7, pv7, v30, pv30 |
| units_today, units_7d, prev_units_7d, units_30d, prev_units_30d | integer | ut, u7, pu7, u30, pu30 (só pedidos `paid`) |
| revenue_7d, prev_revenue_7d, revenue_30d, prev_revenue_30d | decimal(12,2) | r7, pr7, r30, pr30 (Σ quantity × unit_price) |
| net_after_fee_7d | decimal(12,2) | n7 = Σ quantity × (unit_price − sale_fee) |
| fees_30d | decimal(12,2) | f30 = Σ quantity × sale_fee |
| conversion_7d, prev_conversion_7d, conversion_30d, prev_conversion_30d | decimal(8,2) | vendas ÷ visitas × 100; nil se visitas = 0 |
| units_delta | integer | u7 − pu7; **nil se u7 = 0 e pu7 = 0** (variação só vale para quem vendeu em alguma das duas semanas) |
| coverage_days | decimal(10,1) | estoque ÷ (u7 ÷ 7); nil se u7 = 0 |
| coverage_30d | decimal(10,1) | estoque ÷ (u30 ÷ 30); nil se u30 = 0 |
| computed_at | datetime | |
Índices: `(ml_account_id, status)` e um por coluna ordenável mais usada (`units_7d`, `revenue_30d`).

"Faturou nos últimos 60 dias" = `revenue_30d + prev_revenue_30d > 0`.
Anúncio sem linha em `ml_costs`: custo nil. Custo = `cost + extra` de `Current.company.ml_costs` pelo `sku`.

## Rotas (já adicionadas pelo orquestrador em `config/routes.rb` — não altere o arquivo)
- `GET /api/painel` → `PainelController#show` (A4)
- `GET /api/items` → `ItemsController#index` (A4)
- `GET /api/abc` → `AbcController#index` (A5)
- `GET /api/abc/items/:id` → `AbcController#show` (A5)
- `POST /api/items/:id/ai-plan` → `AiPlansController#create` (A5)
Todos com `account_id` obrigatório (query), resolvido por um concern `CurrentAccount` (criado pelo orquestrador): `before_action :set_account` → `Current.account = Current.company.ml_accounts.find(params.require(:account_id))`. Anúncio: `Current.account.item_metrics.find_by!(item_id:)` / `Current.account.ml_items.find`. Nunca `MlItem.find` direto.
