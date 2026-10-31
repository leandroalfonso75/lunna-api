# Configurações

Cadastros da empresa e das contas conectadas.

## Abas
- **Empresa:** nome, **Impostos e margem** (`tax_pct`, margem mínima, margem máxima nas promoções (`max_margin_pct`, opcional), cortes da Curva ABC, limites de variação) e a IA
  (chave e modelo do OpenRouter, por empresa). A rotina automática das Promoções (liga/desliga, modo, horário e dias)
  e as demais regras da automação ficam na aba **Promoções** desta tela (`components/settings/PromocoesTab.vue`, `PATCH /api/company` com `promo_*`), desde 30/10.
- **Anúncios:** base do custo de Ads por unidade (últimos 7, 15 ou 30 dias fechados; `companies.ads_cost_days`),
  usada em Anúncios (Custo Ads, Lucro pós Ads) e em Promoções (margem pós Ads).
- **Ads:** limite máximo de investimento diário em Product Ads (`companies.ads_daily_budget_max`, R$, opcional, soma
  dos orçamentos diários das campanhas ativas), teto que as sugestões de estrutura de campanhas (Ads → Análise)
  respeitam: campanha nova sempre com orçamento diário e ROAS Objetivo a preencher; se não cabe, redução de orçamento
  de outra campanha.
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

## Atenção: desconectar uma conta do Mercado Livre
- Hoje "Desconectar" apaga a conta e **todos os dados dela** no Lunna (vendas, anúncios, Ads, promoções, limites de
  promoção por anúncio e histórico). Reconectar baixa de novo os últimos 95 dias do ML, mas os limites por anúncio e o
  histórico se perdem. Pendência: trocar por pausar a conta, sem apagar dados.
- Reconectar no ambiente local exige um endereço https para o retorno do login (túnel temporário) cadastrado como URL
  de redirecionamento no DevCenter do ML.
