---
name: secao-curva-abc
description: Use ao alterar a página Curva ABC do Lunna (classificação A/B/C, lucro e margem, preço sugerido, plano com IA).
---

1. Leia `docs/secoes/curva-abc.md` e a seção 8 de `docs/SPEC.md`.
2. Código principal: `app/services/abc/`, `app/services/ai/`, `abc_controller.rb`, `ai_plans_controller.rb`; front `app/pages/curva-abc.vue` e `components/abc/`.
3. Atenção: hoje usa custo manual (`ml_costs`), não o do Olist nem as despesas fixas; alinhar com Anúncios é pendência registrada.
4. Mudou regra ou arquivo? Atualize `docs/secoes/curva-abc.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md), por exemplo `spec/services/abc`.
