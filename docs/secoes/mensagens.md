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
- **Excluir conversa** (`DELETE /api/messages/:pack_id`): o ML não apaga mensagens de pós-venda; a conversa só sai da lista
  do Lunna (`ml_conversations.hidden_at`) e volta se o comprador escrever de novo (`MlConversation.visible`).
- **Ponto vermelho no menu** (`GET /api/attention`): conversas abertas cuja última mensagem é do comprador ou do ML
  (bloqueadas pelo ML não contam). O filtro "Aguardando você" usa a mesma regra.
- Mensagens do assistente do ML aparecem destacadas ("Mercado Livre") e não viram o "comprador" da conversa.
- Tela: `app/pages/mensagens.vue`, `components/mensagens/ConversationCard.vue` e o mesmo `QuestionTemplatesMenu.vue`
  (`kind="mensagem"`). API: `messages_controller.rb`, `Ml::Sync::Messages`, `MlConversation`, `MlMessageSend`.
- **Regra:** nunca enviar mensagem real para testar.

## Atualização de 10/11/2026

- **Conversa com o assistente de IA do ML** (`conversations/ai-seller`): a resposta vai pelo caminho da conversa e para o
  agente (`ml_conversations.conversation_path`, `agent_id`); evita o 409 "conversation ID invalid".

## Avisos do Mercado Livre (12/11/2026)

- Mensagem do ML (nem vendedor nem comprador) logo depois da resposta do vendedor, como "Resposta enviada ao comprador.", é
  só aviso: a conversa não fica "Aguardando você" nem acende o ponto vermelho. Mensagem do ML antes da resposta (o
  assistente perguntando o que responder) continua contando como pedido de resposta (`Ml::Sync::Messages.effective_last_from`).
