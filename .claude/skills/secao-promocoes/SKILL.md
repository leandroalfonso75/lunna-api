---
name: secao-promocoes
description: Use ao alterar a página Promoções do Lunna (Central de Promoções do Mercado Livre, melhor oferta por margem, margem mínima/máxima por anúncio e SKU, exportação, rotina das 03:00).
---

1. Leia `docs/secoes/promocoes.md` (regra de margem, escolha da melhor oferta, fases e o que ainda não existe).
2. Código principal: `app/services/painel/promotions_query.rb`, `promotion_evaluator.rb`, `promotion_settings.rb`, `promotion_actions.rb`, `promotions_controller.rb`, `app/services/ml/sync/promotions.rb`, `app/jobs/ml/promotions_sync_job.rb`, `promotions_apply_job.rb`; front `app/pages/promocoes.vue` e `components/promocoes/` (repositório `lunna-web-radar`).
3. Margem = (preço + parte do ML − custo − tarifa − frete − imposto − despesas fixas) ÷ preço; custo, frete, imposto e despesas iguais aos da seção Anúncios. Melhor oferta = maior margem dentro da mínima e da máxima (do anúncio ou, sem ela, as gerais de Configurações).
4. Respeite: escrita no Mercado Livre (aderir, ajustar, sair, trocar) só por `Painel::PromotionActions`, só administradores, com confirmação na tela e registro em `ml_promotion_actions`; sem retentativa automática; a rotina automática só depois do modo simulação aprovado pelo usuário.
5. Mudou regra ou arquivo? Atualize `docs/secoes/promocoes.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md).
