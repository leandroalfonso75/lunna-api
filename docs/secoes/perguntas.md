# Seção Perguntas (08/11/2026)

Perguntas dos compradores nos anúncios do Mercado Livre, com resposta pelo Lunna e respostas padrão da empresa.

- **Importação** (`Ml::Sync::Questions`, em `Ml::Sync::Run#sync_questions`): `/questions/search?api_version=4`, mais novas
  primeiro; a cada rodada as sem resposta inteiras e as recentes até uma página sem mudança; todas 1x por dia
  (`ml_accounts.questions_synced_at`). Tabela `ml_questions`.
- **Responder** (`POST /api/questions/:id/answer`): `POST /answers` no ML (o ML entrega ao comprador). Só admin, com
  `confirm: true`, até 2000 caracteres, só pergunta sem resposta; cada envio fica em `ml_question_answers` (ok/erro).
- **Respostas padrão** (`question_templates`, por empresa): `GET/POST /api/question_templates`, `PATCH/DELETE /:id`
  (escrita só admin). Na tela: botão "Respostas padrão" em cada pergunta (Aplicar preenche o campo; menu "…" com Editar e
  Excluir; "Incluir resposta padrão" no topo) e também no topo da página (para gerenciar sem pergunta aberta).
- Tela: `app/pages/perguntas.vue`, `components/perguntas/QuestionCard.vue`, `QuestionTemplatesMenu.vue`.
