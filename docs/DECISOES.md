# Decisões — Lunna (adaptação SaaS da SPEC)

`docs/SPEC.md` é a especificação original (single-seller). Este arquivo registra o que muda para o Lunna ser SaaS multi-empresa e **prevalece** sobre a SPEC onde houver conflito. Decisões fechadas com o dono do produto em 2026-09-24.

## 1. Princípios (inegociáveis)

- **Toda regra de negócio no Ruby**: períodos, métricas, KPIs, alertas, Curva ABC, grupos, lucro/margem, preço sugerido, custo máximo, motor de sugestões, prompt da IA, e também filtro, busca, ordenação e paginação da tabela (`GET /api/items`). O Nuxt só exibe: layout, formatação (BRL, números pt-BR, datas), cores a partir de estados prontos (`ok`/`warn`/`bad`/`info`, `up`/`down`/`flat`, `*_state`), envio dos filtros como query params (debounce 300 ms, cancelando a anterior) e polling a cada 3 min com a aba visível.
- **Somente leitura no Mercado Livre**: nenhum endpoint escreve no ML (nada de PUT/POST em /items). Só `POST /oauth/token` é escrita permitida.
- **Não inventar campos da API do ML**: usar exatamente os endpoints e campos da SPEC seção 3.
- **Parâmetros de negócio nunca fixos no código**: lidos da empresa (seção 3 abaixo).
- **Fuso**: todos os cálculos de dia em `America/Sao_Paulo` (`config.time_zone`). Agrupar por dia em SQL com `(coluna AT TIME ZONE 'America/Sao_Paulo')::date`. O dia das visitas do ML é a data da string (10 primeiros caracteres), sem converter fuso.
- **Testes**: RSpec + FactoryBot + WebMock. Nenhum teste chama a API real do ML nem da Anthropic (`WebMock.disable_net_connect!(allow_localhost: true)`); respostas do ML em fixtures JSON em `spec/fixtures/ml/`.

## 2. Multi-empresa (tenancy)

- `companies` 1—N `users` (um usuário pertence a exatamente uma empresa). Papéis: `admin` | `member`. O usuário do cadastro é `admin`. Não é permitido remover nem rebaixar o último admin, nem o usuário remover a si mesmo.
- `companies` 1—N `ml_accounts` (contas do Mercado Livre). **Nada fixo de seller**: `allowed_seller_id` não existe. Qualquer empresa conecta qualquer conta ML. `ml_accounts.seller_id` é **único global**: uma conta ML pertence a uma só empresa. Reconectar a mesma conta na mesma empresa atualiza tokens; tentar conectar numa segunda empresa é recusado (`outra_empresa`).
- Configuração global (env) é só o app do ML (`ML_CLIENT_ID`, `ML_CLIENT_SECRET`) e a chave da Claude API.
- **Escopo obrigatório**: toda leitura parte de `Current.company`. Conta: `Current.company.ml_accounts.find(params[:account_id])`. Anúncio: `account.ml_items` / `account.item_metrics` — nunca `MlItem.find` direto (IDs MLB são públicos; buscar sem escopo vazaria dados entre empresas). `ml_order_items` sempre via `ml_orders` da conta. Nunca aceitar `company_id` de params.
- O painel mostra **uma conta por vez**. Todo endpoint de leitura/sync/IA recebe `account_id` (UUID da `ml_accounts`) como query param; conta de outra empresa ou inexistente → 404.
- Desconectar conta apaga todos os dados dela (FKs `on_delete: :cascade`).

## 3. Parâmetros de negócio por empresa

A tabela key/value `ml_app_config` da SPEC vira colunas tipadas em `companies` (com defaults = valores da SPEC), editáveis por admin em Configurações:

| Coluna | Default | Uso |
|---|---|---|
| `tax_pct` | 11.3 | imposto (8.4, 8.5) |
| `min_margin_pct` | 9 | margem líquida mínima |
| `abc_cut_a` | 80 | corte da curva A (acumulado antes < 80) |
| `abc_cut_b` | 95 | corte da curva B |
| `group_up_pct` | 10 | grupo "Vendendo" (variação ≥ +10%) |
| `group_down_pct` | -15 | grupo "Em queda" (variação < −15%) |

Estado de sincronização por conta vai para `ml_accounts`: `orders_backfilled_at` (substitui `orders_backfilled`), `visits_synced_at` (substitui `last_visits_ms`).
`ml_costs` é por empresa (`company_id`, `sku` único), compartilhado entre as contas da empresa; sem UI na v1 (SPEC 12).

## 4. Autenticação do painel

- `has_secure_password` (bcrypt) + tabela `sessions` (`user_id`, `token_digest` = SHA256 do token, `expires_at` = 30 dias, `ip`, `user_agent`). O token bruto (`SecureRandom.urlsafe_base64(32)`) só existe na resposta do login/cadastro; o banco guarda o digest.
- Cliente envia `Authorization: Bearer <token>`. Ausente, inválido ou expirado → 401 `{errors: ["não autenticado"]}`.
- `rate_limit` nativo do Rails 8 em sign_in (10/3 min por IP) e sign_up (5/h por IP), sempre com `with:` renderizando 429 `{errors: ["Muitas tentativas. Tente de novo em instantes."]}`.
- Senha mínima: 8 caracteres. E-mail normalizado (`normalizes :email, with: ->(e) { e.strip.downcase }`) e único global.
- Fora da v1: esqueci-senha / e-mails (sem SMTP).

## 5. OAuth com o Mercado Livre (adapta SPEC 2)

- O navegador não carrega o Bearer num redirect, então `GET /auth/ml/start` vira **`POST /api/ml_accounts/authorize`** (autenticado, admin) → `200 {url}`. O front faz `window.location = url`. Gera `state` (UUID), grava em `ml_oauth_states` com `company_id` e `user_id`, apaga states > 1 h. Sem `ML_CLIENT_ID`/`ML_CLIENT_SECRET` → 422 `{errors: ["Integração com o Mercado Livre não configurada."]}`.
- `redirect_uri` = `"#{ENV.fetch('API_URL')}/auth/ml/callback"` (idêntico ao cadastrado no DevCenter).
- **`GET /auth/ml/callback`** (público) sempre responde **302** para `"#{ENV.fetch('FRONT_URL')}/configuracoes?aba=contas&ml=<resultado>"`:

| Situação | `ml=` |
|---|---|
| veio `error` | `cancelada` |
| sem `code` ou `state` | `link_invalido` |
| state inexistente ou > 1 h | `expirada` |
| usuário do state não é mais admin da empresa | `sem_permissao` |
| app sem client id/secret | `erro_config` |
| troca do code falhou | `erro` |
| resposta sem `refresh_token` | `sem_offline_access` |
| seller já vinculado a outra empresa | `outra_empresa` |
| sucesso | `conectada` |

- O state é consumido numa transação com lock (uso único). A empresa vem **só** do state.
- Gravação: `find_or_initialize_by(seller_id:)` + `save!` (não upsert), `status: "active"`, `last_error: nil`, `expires_at = agora + expires_in` (padrão 21.600 s). Em seguida enfileira a primeira sync.
- **Renovação** (SPEC 2.7) dentro de `account.with_lock` (reload, renova se faltar < 10 min). Grava sempre o novo `access_token` **e** o novo `refresh_token`. Falha → `status: "reauth_required"`, `last_error: "Falha ao renovar token … Autorize de novo."` e a rodada termina `ok=false`. O agendador pula contas `reauth_required` até nova autorização.

## 6. Sincronização (adapta SPEC 4)

- Solid Queue no mesmo banco (sem Redis). `config/recurring.yml`: `Ml::SyncAllJob` a cada 5 min (enfileira `Ml::SyncJob` para cada conta `active`) e `CleanupJob` diário (states > 1 h, sessões expiradas, `ml_sync_runs` > 30 dias).
- Uma rodada por vez por conta: `limits_concurrency to: 1, key: ->(account_id, *) { account_id }, duration: 20.minutes, on_conflict: :discard` + regra da SPEC (rodada iniciada há < 6 min e não terminada → ignora "rodada anterior ainda em andamento"; `POST /api/sync` responde 409). Rodadas não terminadas com mais de 6 min são marcadas `ok=false, detail: "interrompida"` ao iniciar a próxima.
- HTTP paralelo com `Thread` simples (5 ou 4 simultâneos conforme a etapa), cada thread em `Rails.application.executor.wrap`, `join` dentro de `ActiveSupport::Dependencies.interlock.permit_concurrent_loads`. Threads só fazem HTTP; **toda gravação no banco no thread principal**.
- Antes de todo `upsert_all`, deduplicar linhas pela chave (itens do mesmo pedido e mesmo anúncio somados). Etapas que atualizam só algumas colunas (qualidade, cadastro/preço) usam `update_all`/`update_columns`, não upsert.
- Pedidos: paginação da SPEC (50/página, offset até 9.950). Teto conhecido de ~10 mil pedidos por janela, marcado com comentário `ponytail:`.
- Ao fim de toda rodada (mesmo com notas): `Painel::ItemMetrics.refresh(account)`.

## 7. Contrato extra (não previsto na SPEC)

Erros sempre `{errors: ["mensagem"]}` com status 401/403/404/409/422/429. Payloads (JSON):

- `user` = `{id, name, email, role}`
- `company` = `{id, name, tax_pct, min_margin_pct, abc_cut_a, abc_cut_b, group_up_pct, group_down_pct}` (números como Float)
- `ml_account` = `{id, seller_id, nickname, status, last_error, connected_at, last_sync: {id, started_at, finished_at, ok, items, orders, detail} | null}`

| Método e rota | Quem | Corpo / resposta |
|---|---|---|
| `POST /auth/sign_up` | público | `{company_name, name, email, password}` → 201 `{token, user, company, ml_accounts: []}` |
| `POST /auth/sign_in` | público | `{email, password}` → 200 `{token, user, company, ml_accounts}`; 401 `E-mail ou senha inválidos.` |
| `DELETE /auth/sign_out` | logado | 204 (apaga a sessão atual) |
| `GET /api/me` | logado | `{user, company, ml_accounts}` |
| `GET /api/company` | logado | `{company}` |
| `PATCH /api/company` | admin | `{name, tax_pct, …}` → `{company}` (recalcula `item_metrics` das contas) |
| `GET /api/users` | admin | `{users: [...]}` |
| `POST /api/users` | admin | `{name, email, password, role}` → 201 `{user}` |
| `PATCH /api/users/:id` | admin | `{name?, role?, password?}` → `{user}` |
| `DELETE /api/users/:id` | admin | 204 |
| `GET /api/ml_accounts` | logado | `{ml_accounts: [...]}` |
| `POST /api/ml_accounts/authorize` | admin | 200 `{url}` |
| `DELETE /api/ml_accounts/:id` | admin | 204 |
| `POST /api/sync?account_id=` | admin | 202 `{run_id}`; 409 se rodando |
| `GET /api/sync/runs?account_id=&limit=20` | logado | `{runs: [{id, started_at, finished_at, ok, items, orders, detail}]}` |
| `GET /auth/ml/callback` | público | 302 (seção 5) |
| `POST /webhooks/ml` | público | 200 vazio, não processa nada na v1 |

Membro (`member`) acessa todas as leituras e o plano com IA; `admin` também gerencia empresa, usuários, contas e sync. Sem permissão → 403 `{errors: ["sem permissão"]}`.

Endpoints da SPEC 10.3–10.6 seguem **exatamente** o formato da SPEC, com `account_id` obrigatório. O campo `account` do `/api/painel` = `{id, nickname, seller_id}`.

## 8. Convenções de código (base: `~/workspace/timeia-api`)

- Rails 8.1, Ruby 3.3, PostgreSQL 16, UUID como PK nas tabelas novas (`companies`, `users`, `sessions`, `ml_accounts`, `ml_sync_runs`); tabelas `ml_*` de dados mantêm as chaves da SPEC (`item_id` string, `order_id` bigint, chaves compostas com `primary_key: [...]`).
- `Current` (`ActiveSupport::CurrentAttributes`: `user`, `company`, `session`). Concern `ErrorRendering` (`render_errors(msgs, status:)`), rotas sem `api/v1`, payloads montados à mão (hashes), serviços `Dominio::Verbo` com `def self.call(...) = new(...).call`.
- Coluna `title` de `ml_items`/`item_metrics` com `collation: "pt-BR-x-icu"`.
- Mensagens para o usuário em português.
- Segredos só em env: nunca em logs (`filter_parameters` inclui token, password, secret, code, access_token, refresh_token) nem em respostas.

## 9. Fora da v1

Escrita no ML, webhook processando tópicos, custos do ERP (tabela existe, sem carga/UI), frete exato por pedido, migração dos dados do Supabase, esqueci-senha.
