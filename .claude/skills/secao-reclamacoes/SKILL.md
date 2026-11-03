---
name: secao-reclamacoes
description: Use ao alterar a seção Reclamações do Lunna (importação das reclamações do Mercado Livre, lista, detalhe, filtros e regras).
---

1. Leia `docs/secoes/reclamacoes.md`.
2. Código principal: `app/services/ml/sync/claims_center.rb` (importação: lista completa/incremental + detalhes 30 por rodada), `app/services/painel/claims_query.rb`, `claims_controller.rb`, `MlClaim`; front `app/pages/reclamacoes.vue` e `components/reclamacoes/` (repositório `lunna-web-radar`).
3. Tudo o que a API do ML devolve fica em jsonb (`raw`, `detail`, `messages`...); colunas próprias só para filtrar e ordenar. Filtros e regras ainda serão definidos com o usuário (03/11/2026): pergunte antes de inventar regra.
4. Respeite: Mercado Livre somente leitura (não responder nem agir nas reclamações sem pedido explícito); anexos não são baixados; mensagens exibidas sem HTML.
5. Mudou regra ou arquivo? Atualize `docs/secoes/reclamacoes.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
