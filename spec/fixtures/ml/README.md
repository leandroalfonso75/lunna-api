# Fixtures da API do Mercado Livre

Respostas usadas pelos specs (WebMock). Formato dos campos segue a SPEC seção 3
e respostas reais já vistas em produção (pedidos/OAuth: timeia-api).
Conta fictícia: seller `430014725`, nickname `LUNNA_SHOP`.

| Arquivo | Endpoint |
|---|---|
| oauth_token.json / oauth_token_no_refresh.json / oauth_refresh.json | POST /oauth/token |
| users_me.json | GET /users/me |
| items_search_scan_1.json, items_search_scan_2.json, items_search_scan_3.json | GET /users/{id}/items/search?search_type=scan |
| items_multiget.json | GET /items?ids=…&attributes=… |
| visits_time_window.json | GET /items/{id}/visits/time_window |
| orders_search.json | GET /orders/search |
| item_performance.json | GET /item/{id}/performance |
| item_description.json | GET /items/{id}/description |
| category_attributes.json | GET /categories/{id}/attributes |
| sale_price.json | GET /items/{id}/sale_price |
| listing_prices.json | GET /sites/MLB/listing_prices |
| fulfillment_stock.json | GET /inventories/{inventory_id}/stock/fulfillment (formato da documentação oficial do ML; ainda não conferido contra uma conta real) |
| shipping_options_free.json | GET /users/{id}/shipping_options/free |
| suggestions_details.json | GET /suggestions/items/{id}/details |
| error_invalid_grant.json | 400 do /oauth/token |
