---
name: secao-curva-abc
description: Use ao alterar a página Curva ABC do Lunna (classificação A/B/C, lucro e margem, preço sugerido, ações recomendadas, plano com IA, gerar/publicar fotos com IA).
---

1. Leia `docs/secoes/curva-abc.md` e a seção 8 de `docs/SPEC.md`.
2. Código principal: `app/services/abc/`, `app/services/ai/` (inclui `photo_generator`, `cover_check`), `app/services/ml/picture_publisher.rb`, `abc_controller.rb`, `ai_plans_controller.rb`, `photo_jobs_controller.rb`; front `app/pages/curva-abc.vue` e `components/abc/` (`AbcPhotoGenerator`).
3. Custo: manual (`ml_costs`) e, sem ele, Olist e variações vendidas; ainda sem despesas fixas (pendência). Fotos: publicar no ML é escrita (admin + confirmação dupla); anúncio de catálogo não aceita troca de fotos (publica no tradicional do mesmo produto); nunca publicar foto real para testar. Geração usa a chave e créditos da OpenRouter do usuário.
4. Mudou regra ou arquivo? Atualize `docs/secoes/curva-abc.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md), por exemplo `spec/services/abc`.
5. Desde 07–09/11/2026: alterar título (family_name, só sem vendas) e ficha técnica (Não se aplica, sem documentos regulatórios), aplicar preço no ML (`Ml::ItemPrice`), frete grátis por faixa a partir de R$ 79 (`ship_cost_tiers`), "Ciente" (`abc_suggestion_acks`), catálogo sem sugestões de conteúdo, vídeo pelo clip (`has_clip`) e filtro por produto/SKU/MLB/palavra. Escritas: admin + confirmação + `ml_item_edits`.
