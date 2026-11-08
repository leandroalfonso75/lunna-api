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

# Seção Mensagens (08/11/2026)

Só mensagens de pós-venda (tag post_sale); reclamações ficam em Reclamações.

- **Importação** (`Ml::Sync::Messages`): o ML não lista todas as conversas; a cada rodada o Lunna relê as não lidas
  (`/messages/unread`), as abertas com mensagem nos últimos 7 dias e as vendas dos últimos 60 dias ainda não conferidas
  (80 por rodada; recentes relidas a cada 12 h; `ml_orders.messages_checked_at`). Sempre `mark_as_read=false`.
  Tabela `ml_conversations` (mensagens em jsonb). Comprador = o da venda (mensagens do assistente do ML vêm de outro id).
- **Enviar** (`POST /api/messages/:pack_id/send`): `POST /messages/packs/{pack}/sellers/{seller}?tag=post_sale`, até 350
  caracteres (`seller_max_message_length`), só conversa `active` (bloqueada: pedido cancelado, reclamação, prazo...).
  Admin, `confirm: true`, registro em `ml_message_sends`.
- **Respostas padrão**: `question_templates.kind = "mensagem"` (até 350 caracteres), mesmo componente das Perguntas.
