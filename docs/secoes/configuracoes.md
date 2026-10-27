# Configurações

Cadastros da empresa e das contas conectadas.

## Abas
- **Empresa:** nome, **Impostos e margem** (`tax_pct`, margem mínima, margem máxima nas promoções (`max_margin_pct`, opcional), cortes da Curva ABC, limites de variação) e a IA
  (chave e modelo do OpenRouter, por empresa).
- **Contas:** contas do Mercado Livre conectadas (conectar e remover). A conta é conectada por OAuth.
- **Usuários:** administradores e membros da empresa.

## Regras
- Tudo é escopado por empresa (`Current.company`); só administradores alteram.
- Mudar os parâmetros de negócio recalcula as métricas (`Painel::ItemMetrics.refresh`).
- A chave da IA fica cifrada e nunca volta para o front (só os 4 últimos caracteres).
- `fixed_expenses_pct` (despesas fixas, padrão 3%) já existe na API e aparece no payload da empresa, mas **ainda não tem
  campo na tela**.
- A conexão com o **Olist ERP** é feita pela API (`POST /api/olist/authorize`, rake `olist:conectar[email]`) ou pelo
  botão "Reconectar ao Olist" da página Produtos; ainda não há aba dela aqui.

## Arquivos
**Front (`lunna-web`)**
- `app/pages/configuracoes/index.vue`, `app/components/settings/` (`EmpresaTab`, `ContasTab`, `UsuariosTab`)
- `app/composables/useSettings.ts`, `app/lib/settingsClient.ts`, `settingsTabs.ts`, `mlCallback.ts`

**API (`lunna-api`)**
- `app/controllers/company_controller.rb`, `ml_accounts_controller.rb`, `users_controller.rb`, `auth/ml_callbacks_controller.rb`
- Modelos `company`, `ml_account`, `user`

## Pendências
- Campo de despesas fixas e aba do Olist.
