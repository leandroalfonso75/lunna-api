---
name: secao-configuracoes
description: Use ao alterar a página Configurações do Lunna (empresa, impostos e margem, contas do Mercado Livre, usuários, chave de IA).
---

1. Leia `docs/secoes/configuracoes.md`.
2. Código principal: `company_controller.rb`, `ml_accounts_controller.rb`, `users_controller.rb`; front `app/pages/configuracoes/index.vue` e `components/settings/`.
3. Promoções: margem máxima geral (`max_margin_pct`) e a rotina das 03:00 (`promo_routine_enabled`, `promo_routine_mode` simulation|apply) ficam na aba Empresa; o modo de aplicação real só liga com ok explícito do usuário.
4. Pendência conhecida: `fixed_expenses_pct` (despesas fixas, 3%) ainda não tem campo na tela e é usado em Anúncios e Vendas.
5. Respeite: tudo escopado por `Current.company`, só administradores alteram, chave de IA cifrada e nunca devolvida ao front.
6. Mudou regra ou arquivo? Atualize `docs/secoes/configuracoes.md` no mesmo commit.
