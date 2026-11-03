# Reclamações

Seção criada em 03/11/2026 a pedido do usuário: primeiro **importar tudo** o que o Mercado Livre informa sobre
reclamações; filtros e regras serão definidos depois, com os dados já no Lunna.

## O que mostra
- Lista de todas as reclamações da conta (cancelamentos, reclamações/mediações e devoluções), mais novas primeiro:
  data de abertura, tipo e etapa, nº da reclamação, venda ligada (foto, título, nº da venda, SKU, valor, comprador),
  motivo, situação (Aberta/Encerrada), quem deve agir e o prazo, e se afeta a reputação.
- Busca por nº da reclamação ou da venda, comprador (apelido ou nome), produto, SKU ou motivo. Paginação de 50.
- Linha de andamento da importação (total, abertas, quantas já têm detalhes completos, quando a lista foi lida).
- Ao clicar: o detalhe completo — o que fazer e prazo (`detail`), venda, mensagens (texto sem HTML; anexos só como
  nome/tipo/tamanho, os arquivos não são baixados), histórico da situação, ações, resolução esperada, evidências,
  devolução, partes que o ML não devolveu na última leitura e, recolhido, os dados completos como vieram da API.
- Venda fora dos 3 meses guardados no Lunna aparece como "fora do Lunna" (a reclamação existe, a venda não).

## Dados e atualização (`Ml::Sync::ClaimsCenter`, dentro da sincronização do ML)
- **Lista:** `/post-purchase/v1/claims/search` com o vendedor como `respondent`, 100 por página. Completa na primeira vez
  e uma vez por dia (`ml_accounts.claims_full_listed_at`); nas demais rodadas, ordenada por `last_updated` e só até a
  última leitura (`claims_listed_at`). A primeira lista (03/11/2026) trouxe 2.481 reclamações, desde 18/04/2020
  (1.530 mediações, 902 cancelamentos, 49 devoluções), em ~2 minutos.
- **Detalhes:** 30 por rodada, mais novas primeiro (reclamação nova ou alterada, e aberta a cada 1 hora):
  `/claims/{id}` (completa), `/detail`, `/messages`, `/status_history`, `/actions-history`, `/expected-resolutions`,
  `/evidences`, `/changes`, `/affects-reputation`, `/v2/claims/{id}/returns` (só com devolução) e
  `/claims/reasons/{id}` (motivo em texto, em cache por 7 dias). 404 = parte que não existe para a reclamação; outro
  erro numa parte fica em `detail_errors` e não impede o resto; 401/403 na reclamação para a rodada.
- Tabela `ml_claims` (uma linha por reclamação, `claim_id` único por conta; apagada junto com a conta): colunas para
  filtrar (tipo, etapa, situação, motivo, datas, quem age, prazo, reputação, pedido) e jsonb com tudo o que a API
  devolve (`raw`, `detail`, `messages`, `status_history`, `actions_history`, `expected_resolutions`, `evidences`,
  `changes_log`, `reputation`, `devolution`, `reason`).
- Venda ligada: pelo pedido (`resource: order`) ou pelo envio (`resource: shipment` → `ml_orders.shipping_id`).
- Somente leitura no Mercado Livre: o Lunna não responde, não anexa nem age nas reclamações.
- O resumo antigo de reclamações dentro das vendas (`ml_orders.claims`, `Ml::Sync::Claims`, motivo na lista de Vendas)
  continua igual.

## API
- `GET /api/claims?account_id=&q=&page=&per_page=` → `claims`, `total`, `page`, `per_page`, `import`.
- `GET /api/claims/:id?account_id=` → a reclamação com tudo (`messages`, `status_history`, `actions_history`,
  `expected_resolutions`, `evidences`, `changes`, `reputation`, `devolution`, `reason_info`, `resolution_raw`, `raw`).

## Arquivos
- API: `app/services/ml/sync/claims_center.rb`, `app/services/painel/claims_query.rb`, `app/controllers/claims_controller.rb`,
  `app/models/ml_claim.rb`, `Ml::Client#claims_search`/`#claim_sub`; testes `spec/services/ml/sync/claims_center_spec.rb`,
  `spec/requests/claims_spec.rb`.
- Front (`lunna-web-radar`): `app/pages/reclamacoes.vue`, `app/components/reclamacoes/ClaimDetailPanel.vue`,
  `app/types/claims.ts`; item "Reclamações" no menu, logo abaixo de Vendas.

## Próximos passos (a definir com o usuário)
- Filtros (tipo, situação, etapa, quem age, prazo, reputação, período, produto) e regras (alertas de prazo, custo das
  reclamações, motivos mais frequentes por produto).
