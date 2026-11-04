---
name: secao-reclamacoes
description: Use ao alterar a seção Reclamações do Lunna (importação das reclamações do Mercado Livre, lista, detalhe, filtros, A atender e resposta, assistente de contestação).
---

1. Leia `docs/secoes/reclamacoes.md`.
2. Código principal: `app/services/ml/sync/claims_center.rb` (importação: lista completa/incremental + detalhes 30 por rodada), `app/services/painel/claims_query.rb`, `app/services/painel/claim_contest.rb` (assistente de contestação), `claims_controller.rb`, `MlClaim`; front `app/pages/reclamacoes.vue` e `components/reclamacoes/` (repositório `lunna-web-radar`).
3. Tudo o que a API do ML devolve fica em jsonb (`raw`, `detail`, `messages`...); colunas próprias só para filtrar e ordenar. Filtros e regras ainda serão definidos com o usuário (03/11/2026): pergunte antes de inventar regra.
4. Respeite: escritas no ML são responder (`Painel::ClaimReply`, `ml_claim_replies`) e resolver (`Painel::ClaimAction`: devolução, reembolso total/parcial, mediação; `ml_claim_actions`), sempre admin + confirm + registro; nunca enviar mensagem real para testar (só WebMock); nenhuma outra ação sem pedido explícito; nunca executar devolução/reembolso/mediação real para testar; a contestação é feita pelo vendedor no ML (o Lunna só sugere o texto e guarda o andamento em `ml_claim_contests`); anexos não são baixados; mensagens exibidas sem HTML.
5. Contestação: o texto de uma contestação aceita vira modelo do mesmo grupo e motivo, mas SEMPRE ajustado às peculiaridades do caso (`ADDONS`/`traits_for`, aviso no card); nunca reaproveitar texto de outro grupo.
6. Mudou regra ou arquivo? Atualize `docs/secoes/reclamacoes.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
