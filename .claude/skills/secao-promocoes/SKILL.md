---
name: secao-promocoes
description: Use ao alterar a página Promoções do Lunna (Central de Promoções do Mercado Livre, melhor oferta por margem, margem mínima/máxima por anúncio e SKU, exportação, rotina das 03:00).
---

1. Leia `docs/secoes/promocoes.md` (regra de margem, escolha da melhor oferta, fases e o que ainda não existe).
2. Código principal: `app/services/painel/promotions_query.rb`, `promotion_evaluator.rb`, `promotion_settings.rb`, `promotions_controller.rb`, `app/services/ml/sync/promotions.rb`, `app/jobs/ml/promotions_sync_job.rb`; front `app/pages/promocoes.vue` e `components/promocoes/` (repositório `lunna-web-radar`).
3. Margem = (preço + parte do ML − custo − tarifa − frete − imposto − despesas fixas) ÷ preço; custo, frete, imposto e despesas iguais aos da seção Anúncios. Melhor oferta = maior margem dentro da mínima (do anúncio ou geral) e da máxima (só do anúncio).
4. Respeite: a fase 1 não escreve no Mercado Livre; qualquer escrita (aderir, editar, sair) só para administradores, com confirmação e registro; a rotina automática só depois do modo simulação aprovado pelo usuário.
5. Mudou regra ou arquivo? Atualize `docs/secoes/promocoes.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
