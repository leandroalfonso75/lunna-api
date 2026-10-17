# Produtos (Olist ERP)

Lista os produtos cadastrados no **Olist ERP (antigo Tiny)**, guardados no banco do Lunna e atualizados sozinhos.

## O que mostra
- Tabela: SKU, produto, situação, preço, promocional, **custo**, **estoque Olist** (disponível), **estoque Full**
  (Mercado Livre) e **estoque total** (Olist + Full).
- **Variações agrupadas no produto pai**: a seta ao lado do nome abre a lista das variações. O pai mostra o estoque somado.
- **Kits**: custo = soma do custo dos componentes; estoque = quantos kits os componentes permitem montar. Ao clicar no
  produto aparece a "Composição do kit".
- Ao clicar numa linha: ID no Olist, GTIN, tipo, depósitos, entradas com saldo (PEPS), datas.
- Busca por nome/SKU/GTIN, filtro de situação, "Atualizar agora" e, para administradores, "Reconectar ao Olist".

## Dados e atualização
- A cada **3 minutos** o servidor lê produtos e estoque do Olist (`Olist::SyncJob`); o usuário pode pedir na hora
  (`POST /api/olist/sync`). A conexão é OAuth2 por empresa; o acesso dura 4 h e a renovação 1 dia, e o worker renova a
  cada 6 h (`Olist::RefreshAllJob`). Se o computador ficar desligado mais de um dia, é preciso reconectar.
- Variações: o Olist só informa o pai dentro do pai (`GET /produtos/{id}`); o Lunna guarda e só relê quando o pai muda.
- Kits: composição lida de `GET /produtos/{id}/kit`.
- **Estoque Full**: lido direto do Mercado Livre por `inventory_id` (`Ml::Sync::FullStock`) e ligado ao produto pelo
  **SKU** (`Olist::FullStock`). Produto excluído no Olist não recebe Full.

## Custo PEPS (Primeiro que Entra, Primeiro que Sai)
Calculado pelas movimentações do Controle de Estoque do Olist (`GET /estoque/{id}/logs-movimentacao`), em
`Olist::Fifo` (função pura, bem testada) e `Olist::SyncCosts` (lotes de 40 produtos por rodada).
- Cada **entrada** vira uma camada com o custo informado; cada **saída** consome da camada mais antiga.
- O custo do produto é o da **camada mais antiga que ainda tem saldo**.
- **Aviso de atenção** quando uma entrada que ainda tem unidades em estoque não tem custo. Entrada sem custo já toda
  consumida é ignorada.
- **Full**: envio do Geral ao Full (observação "Envio ..." ou "NFT ...") é transferência e **não** consome camadas; a
  venda registrada no depósito do Full consome; balanço no Full só zera o registro.
- O detalhe mostra a diferença entre o que o histórico explica e o estoque de hoje (kits, variações e SKUs diferentes
  entre Olist e Mercado Livre podem causar diferença).
- **Histórico que não fecha:** se as saídas registradas superam as entradas (ou deixam menos unidades que o estoque
  atual, Olist + Full), as camadas são refeitas da entrada mais recente para trás até cobrir o estoque atual
  (`Olist::Fifo`, parâmetro `current_stock`). Sem isso o produto ficava sem custo mesmo com entradas com preço.
- Ordem de custo usada em outras telas (`Olist::UnitCost`): PEPS → custo cadastrado no produto → custo médio → custo
  da última entrada com preço (produto sem saldo, fonte `ultima_entrada`); kit = soma dos componentes.
- Só continua sem custo quem não tem nenhuma entrada com preço no Controle de Estoque (entrada sem valor ou sem entrada).

## Escrita no Olist (API, ainda sem tela)
`PATCH /api/olist/products/:id/price` e `POST /api/olist/products/:id/stock`: só administradores, exigem `confirm=true`,
registram quem/quando/antes/depois em `olist_changes` e nunca repetem sozinhas. Testado só com respostas simuladas.

## Arquivos
**Front (`lunna-web`)**
- `app/pages/produtos.vue`, `app/components/produtos/OlistProductRow.vue`
- `app/composables/useOlistProducts.ts`, `app/lib/olistClient.ts`

**API (`lunna-api`)**
- Controllers: `olist_controller.rb` (conexão, sync, status), `olist_products_controller.rb` (lista, detalhe, escrita),
  `auth/olist_callbacks_controller.rb` (retorno do OAuth)
- Serviços `app/services/olist/`: `oauth`, `client`, `sync_products`, `sync_costs`, `fifo`, `kit_resolver`, `unit_cost`,
  `full_stock`, `product_payloads`, `change_product`
- Jobs `app/jobs/olist/`: `sync_job`, `sync_all_job`, `sync_costs_job`, `refresh_all_job` (agendados em `config/recurring.yml`)
- Modelos: `olist_connection`, `olist_product`, `olist_sync_run`, `olist_change`, `olist_stock_movement`, `ml_full_stock`

## Pendências
- Validar com SKUs de custo conhecido a conta do PEPS (hoje bate em 55 de 99 produtos com estoque).
- Ainda sem tela para editar preço/estoque.
- Credenciais: `OLIST_CLIENT_ID` e `OLIST_CLIENT_SECRET` no `.env`; URL de retorno `<API_URL>/auth/olist/callback`.
