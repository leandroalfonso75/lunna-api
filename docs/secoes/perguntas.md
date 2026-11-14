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
- **Sugerir resposta** (`POST /api/questions/:id/suggest`, `Ai::QuestionAnswerSuggestion`): a IA escreve a resposta com os
  dados do anúncio (título, ficha, descrição, preço, estoque, frete), as **fotos do anúncio** (até 10, modelo com visão
  `google/gemini-2.5-flash`; cores, tons lado a lado, embalagem), as respostas já dadas no mesmo anúncio e nos anúncios
  do mesmo SKU (`Painel::ItemSkus.items_with_skus`) e o tom das respostas recentes. Só preenche o campo e mostra as
  fontes; não inventa (sem dado, diz que vai confirmar). Tons de maquiagem: compara claridade e subtom e confere pela
  numeração (sobe do mais claro para o mais escuro).
- **Excluir pergunta** (`DELETE /api/questions/:id`): `DELETE /questions/{id}` no ML; some do anúncio para todos e não dá
  para desfazer (admin, `confirm: true`). Perguntas `DELETED` saem das listas.
- **Ponto vermelho no menu** (`GET /api/attention`): perguntas sem resposta.
- **Regra:** nunca enviar resposta real para testar.

## Quem perguntou (13/11/2026)

- Cada pergunta mostra quem perguntou: se a pessoa já comprou da loja, o nome e o apelido da venda e o selo "já
  comprou"; senão, o apelido público do ML (`GET /users/{id}`). `ml_questions.from_nickname` / `from_name`, preenchidos
  na sincronização (`Ml::Sync::Questions.fill_askers`, até 60 por rodada, sem resposta primeiro).

- **Respondida ou apagada direto no ML** (14/11/2026): pergunta sem resposta no Lunna que não vem mais na busca de sem
  resposta do ML é relida (`GET /questions/{id}`): 404 = apagada (fica DELETED e sai da lista); senão grava o estado
  atual. Só roda quando a busca de sem resposta veio inteira (`Ml::Sync::Questions.reconcile_unanswered`).
