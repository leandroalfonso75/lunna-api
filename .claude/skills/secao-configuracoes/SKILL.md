---
name: secao-configuracoes
description: Use ao alterar a página Configurações do Lunna (empresa, impostos e margem, anúncios, ads, promoções, contas do Mercado Livre, usuários, chave de IA).
---

1. Leia `docs/secoes/configuracoes.md`.
2. Código principal: `company_controller.rb`, `ml_accounts_controller.rb`, `users_controller.rb`; front `app/pages/configuracoes/index.vue` e `components/settings/`.
3. Promoções: a margem máxima geral (`max_margin_pct`) fica na aba Empresa; a rotina automática (liga/desliga, modo, horário, dias) e as demais opções da automação ficam na aba Promoções de Configurações (`PromocoesTab.vue`, `PATCH /api/company` com `promo_*`).
4. Anúncios: base do custo de Ads por unidade (`ads_cost_days`, 7/15/30; `AnunciosTab.vue`). Ads: limite máximo de investimento diário (`ads_daily_budget_max`, `AdsTab.vue`), teto das sugestões de estrutura de campanhas (ver skill `secao-ads`). Abas em `app/lib/settingsTabs.ts`.
5. Pendência conhecida: `fixed_expenses_pct` (despesas fixas, 3%) ainda não tem campo na tela e é usado em Anúncios e Vendas.
6. Respeite: tudo escopado por `Current.company`, só administradores alteram, chave de IA cifrada e nunca devolvida ao front.
7. Mudou regra ou arquivo? Atualize `docs/secoes/configuracoes.md` no mesmo commit.
