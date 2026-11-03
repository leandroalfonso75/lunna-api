# Reclamações

Seção criada em 03/11/2026 a pedido do usuário: primeiro **importar tudo** o que o Mercado Livre informa sobre
reclamações; filtros e regras serão definidos depois, com os dados já no Lunna.

## O que mostra
- Lista de todas as reclamações da conta (cancelamentos, reclamações/mediações e devoluções), mais novas primeiro:
  data de abertura, tipo e etapa, nº da reclamação, venda ligada (foto, título, nº da venda, SKU, valor, comprador),
  motivo, situação (Aberta/Encerrada), quem deve agir e o prazo, e se afeta a reputação.
- **Devolução habilitada** (Sim/Não; "carregando…" antes dos detalhes): Sim quando há devolução no ML (`devolution`) ou
  uma ação do ML que a autoriza (`allow_return`, `generate_return`, `generate_return_async`). **Devolução efetivada**
  (pedido do usuário em 03/11/2026), pelo status da devolução (`/v2/claims/{id}/returns`): `delivered` → Devolvida;
  `shipped` → A caminho; `label_generated`/`pending`/`ready_to_ship` → Aguardando (ainda no prazo de postagem);
  `expired`/`cancelled`/`failed`/`not_delivered` → Não devolvida. Autorizada sem devolução gerada: Aguardando se a
  reclamação está aberta, Não devolvida se encerrada. A devolução é sempre consultada (404 = não há): o ML nem sempre
  marca "return" em `related_entities` de reclamação encerrada (até 03/11 isso deixava devoluções de fora; refeito).
- **Reembolso** (pedido do usuário em 03/11/2026): pelos pagamentos da venda (`transaction_amount_refunded` x
  `transaction_amount`): Reembolso integral, Reembolso parcial (com o valor e o pago) ou Sem reembolso ("até agora" se a
  reclamação está aberta). Venda fora do Lunna: pelo que a reclamação registra (resolução esperada `partial_coverage`/
  `partial_refund` aceita → parcial; `refund` aceita, `status_money: refunded` da devolução ou resolução
  `payment_refunded` → integral; senão, sem).
- **Custo com frete** (frete da devolução): Não quando não houve devolução ou ela não foi postada (expirou/cancelada);
  Sim quando foi entregue ou está a caminho; "Sim (previsto)" quando a etiqueta existe e ainda não foi postada. Valor:
  o que o ML informa na mensagem ("custo do frete da etiqueta de devolução ... R$ X", `return_shipping.stated_cost`,
  lido na importação) ou, sem isso, o custo do envio de retorno que ficou com o vendedor (`/shipments/{id}/costs`,
  `receiver.cost`, em `ml_claims.return_shipping`). Quando o ML aplicou cobertura na reclamação (`applied_coverage`), a
  tela avisa "cobertura do ML": o custo pode ter sido reembolsado ao vendedor (em 03/11, 97 de 101 casos com frete).
- **Período** (pela data de abertura, como em Vendas; pedido do usuário em 03/11/2026): Todas (padrão), Hoje, Ontem,
  7, 30, 60 dias, 3 e 12 meses, **Mês** (lista com todos os meses que têm reclamação, o atual primeiro) ou datas
  escolhidas (sem o limite de 92 dias de Vendas: as reclamações vêm desde 2020). API: `period`, `month=YYYY-MM` ou
  `from`/`to`; a resposta traz `period` e `months`.
- **Ordenação** clicando no título: Aberta em, Reclamação (tipo), Motivo, Situação, Devolução habilitada, Devolução
  efetivada, Reembolso, Custo com frete (pelo valor) e Reputação; clicar de novo inverte. API: `sort` (date, type,
  reason, status, return_enabled, return_state, refund, freight, reputation) e `dir`. Como devolução, reembolso e
  frete são calculados, a lista inteira do período é montada e ordenada antes de paginar (~0,2 s para 2.481);
  reclamação ainda sem detalhes vai para o fim em qualquer ordem.
- **A atender** (pedido do usuário em 03/11/2026): botão grande abaixo do período, com contador e ponto pulsante quando
  há pendência. "A atender" = reclamação aberta em que o ML aguarda o vendedor (`detail.action_responsible` seller/
  respondent ou ação obrigatória do vendedor em `players[respondent].available_actions`). Ao lado, "Abertas" (todas as
  abertas, com quantas o vendedor pode responder). As duas visões mostram cartões, pelo prazo (as que aguardam o
  vendedor primeiro): prazo com contagem (vermelho < 24 h e amarelo < 72 h só quando o prazo é do vendedor), quem age,
  motivo, o que o comprador quer (resolução esperada), reputação, custos (reembolso, frete da devolução, cobertura do
  ML), devolução, ações liberadas pelo ML, "o que fazer" do ML e a última mensagem. API: `view=atender|abertas`;
  contadores em `attention` (to_attend, open, can_reply), sempre sobre todas as abertas.
- **Responder** (escrita no ML, não se desfaz): `POST /api/claims/:id/reply` (admin, `receiver_role` complainant ou
  mediator, `message` até 3.500 caracteres, `confirm: true`), `Painel::ClaimReply` →
  `POST /post-purchase/v1/claims/{id}/actions/send-message`. Só para quem o ML libera agora (ação
  `send_message_to_complainant`/`send_message_to_mediator` do vendedor). Na tela: botão "Responder" quando a reclamação aguarda o vendedor, ou "Responder (opcional)" (mais discreto) quando não
  há obrigação de resposta → destinatário e texto
  → "Enviar resposta" → "Confirmar envio ao Mercado Livre" (segundo clique, com aviso). Cada envio fica em
  `ml_claim_replies` (quem, quando, para quem, texto, sent/failed, erro) e a reclamação é relida em seguida. Testado só
  com respostas simuladas; o primeiro envio real confirma se o app do Lunna tem permissão de escrita em reclamações
  (403 = falta liberar no DevCenter).
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
- **Reputação:** `/affects-reputation` responde `affects_reputation` como **texto** ("affected" / "not_affected"), não
  como verdadeiro/falso. `affects_reputation` (booleano) = `ClaimsCenter.reputation_flag` (affected → true,
  not_affected → false, outro valor → nil) e o texto original fica em `reputation_status`. Até 03/11/2026 15h o texto era
  convertido direto e "not_affected" virava "Afeta" (corrigido pela migration `AddReputationStatusToMlClaims`, que
  recalculou tudo a partir do jsonb `reputation`; conferido com a venda #2000019300486644, que não afetou a reputação).
- Venda ligada: pelo pedido (`resource: order`) ou pelo envio (`resource: shipment` → `ml_orders.shipping_id`).
- Somente leitura no Mercado Livre: o Lunna não responde, não anexa nem age nas reclamações.
- O resumo antigo de reclamações dentro das vendas (`ml_orders.claims`, `Ml::Sync::Claims`, motivo na lista de Vendas)
  continua igual.

## API
- `GET /api/claims?account_id=&q=&page=&per_page=&period=|month=|from=&to=&sort=&dir=` → `claims`, `total`, `page`, `per_page`,
  `sort`, `dir`, `period`, `months`, `import`.
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
