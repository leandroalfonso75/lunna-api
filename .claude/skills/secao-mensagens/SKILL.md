---
name: secao-mensagens
description: Use ao alterar a página Mensagens do Lunna (mensagens de pós-venda com compradores do Mercado Livre, envio, respostas padrão, excluir da lista).
---

1. Leia `docs/secoes/mensagens.md`.
2. Código: `messages_controller.rb`, `Ml::Sync::Messages`, `MlConversation`, `MlMessageSend`, `attention_controller.rb`; front `app/pages/mensagens.vue`, `components/mensagens/ConversationCard.vue`, `components/perguntas/QuestionTemplatesMenu.vue` (`kind="mensagem"`).
3. Leitura sempre com `mark_as_read=false`. Envio até 350 caracteres, só conversa `active`, admin + confirmação + registro. O ML não apaga mensagens: excluir só esconde no Lunna.
4. Comprador = o da venda (mensagens do assistente do ML vêm de outro usuário). Nunca enviar mensagem real para testar.
5. Mudou regra ou arquivo? Atualize a doc e `spec/requests/messages_spec.rb`; testes com `RAILS_ENV=test`.
6. Conversa com o assistente de IA do ML (`conversations/ai-seller`) responde no caminho da conversa e ao agente (`conversation_path`, `agent_id`).
7. Aviso do ML depois da resposta do vendedor ("Resposta enviada ao comprador.") não deixa a conversa aguardando (`effective_last_from`).
