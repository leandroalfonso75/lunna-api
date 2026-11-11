---
name: secao-perguntas
description: Use ao alterar a página Perguntas do Lunna (perguntas dos compradores no Mercado Livre, responder, sugerir resposta com IA, respostas padrão, excluir pergunta).
---

1. Leia `docs/secoes/perguntas.md`.
2. Código: `questions_controller.rb`, `Ml::Sync::Questions`, `Ai::QuestionAnswerSuggestion`, `Painel::ItemSkus`, modelos `MlQuestion`, `MlQuestionAnswer`, `QuestionTemplate`; front `app/pages/perguntas.vue`, `components/perguntas/`.
3. Escritas no ML (responder, excluir): só admin, com confirmação e registro. Nunca enviar resposta real nem apagar pergunta real para testar.
4. A sugestão da IA só preenche o campo; usa dados, fotos (modelo com visão) e respostas do mesmo anúncio/SKU; não inventa.
5. Mudou regra ou arquivo? Atualize a doc e `spec/requests/questions_spec.rb`; testes com `RAILS_ENV=test`.
