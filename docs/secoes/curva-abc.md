# Curva ABC

Classifica os anúncios por faturamento (A, B, C) e mostra lucro, margem e sugestões.

## O que mostra
- Resumo por curva, abas A/B/C, tabela com lucro e margem por unidade e no mês, e detalhe com **plano de ação com IA**.
- A IA (OpenRouter) usa a chave e o modelo configurados pela empresa em Configurações > Empresa.

## Regras (resumo; base em `docs/SPEC.md` seção 8 e `docs/DECISOES.md`)
- Cortes da curva e margem mínima por empresa (`abc_cut_a`, `abc_cut_b`, `min_margin_pct`).
- Lucro/sobra por unidade e no mês (`Abc::Economics`): preço − tarifa − frete − imposto − custo (custo manual `ml_costs`).
- Preço sugerido e custo máximo (`Abc::PriceSuggestion`), diagnóstico e recomendações (`Abc::SuggestionEngine`).
- **Atenção:** a Curva ABC ainda usa o custo manual (`ml_costs`) e o imposto da empresa; ela **não** usa o custo do Olist
  nem as despesas fixas, ao contrário da tabela de Anúncios. Alinhar os dois é uma pendência.

## Arquivos
**Front (`lunna-web`)**
- `app/pages/curva-abc.vue`, `app/components/abc/` (`AbcTable`, `AbcDetail`, `AiPlanPanel`)
- `app/composables/useAbc.ts`, `useAiPlan.ts`; `app/lib/aiPlanClient.ts`, `aiPlanRunner.ts`

**API (`lunna-api`)**
- `app/controllers/abc_controller.rb`, `ai_plans_controller.rb`
- `app/services/abc/` (`classifier`, `economics`, `params`, `price_suggestion`, `report`, `suggestion_engine`) e `app/services/ai/`
- `app/jobs/ai/` (geração do plano em segundo plano, lida por polling)

## Pendências
- Usar o custo do Olist e as despesas fixas, para ficar coerente com Anúncios.
