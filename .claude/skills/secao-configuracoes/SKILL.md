---
name: secao-configuracoes
description: Use ao alterar a página Configurações do Lunna (empresa, impostos e margem, contas do Mercado Livre, usuários, chave de IA).
---

1. Leia `docs/secoes/configuracoes.md`.
2. Código principal: `company_controller.rb`, `ml_accounts_controller.rb`, `users_controller.rb`; front `app/pages/configuracoes/index.vue` e `components/settings/`.
3. Respeite: tudo escopado por `Current.company`, só administradores alteram, chave de IA cifrada e nunca devolvida ao front.
4. Mudou regra ou arquivo? Atualize `docs/secoes/configuracoes.md` no mesmo commit.
