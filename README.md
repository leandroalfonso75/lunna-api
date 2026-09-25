# lunna-api

API do **Lunna — Painel de Anúncios do Mercado Livre**, um SaaS multi-empresa: cada empresa
cadastra seus usuários e conecta uma ou mais contas do Mercado Livre; a API sincroniza anúncios,
visitas, pedidos, qualidade e referência de preço a cada 5 minutos e entrega KPIs, alertas,
tabela filtrável e Curva ABC já calculados. O front é o [lunna-web](../lunna-web).

- **Especificação**: [`docs/SPEC.md`](docs/SPEC.md) (original) e [`docs/DECISOES.md`](docs/DECISOES.md)
  (adaptação SaaS — prevalece). Contrato das métricas por anúncio: [`docs/METRICS.md`](docs/METRICS.md).
- **Stack**: Ruby 3.3 · Rails 8.1 (modo API) · PostgreSQL 16 · Solid Queue e Solid Cache no mesmo
  banco (sem Redis) · Faraday (ML e OpenRouter) · RSpec + FactoryBot + WebMock.
- **Regra de ouro**: toda regra de negócio (períodos, métricas, alertas, Curva ABC, lucro, sugestões,
  filtros e ordenação da tabela) mora aqui. O front só exibe.
- **Somente leitura no Mercado Livre**: o único POST ao ML é o `/oauth/token`.

## Configurar o app no DevCenter do Mercado Livre

1. Em <https://developers.mercadolivre.com.br/devcenter>, crie (ou edite) o aplicativo.
2. **Redirect URI**: `<API_URL>/auth/ml/callback` — em produção `https://api.lunnashop.com.br/auth/ml/callback`
   (em dev: `http://localhost:3100/auth/ml/callback`). Precisa ser idêntica ao `API_URL` da API.
3. **Permissões**: leitura e escrita (a escrita fica reservada para funções futuras) e **`offline_access`**
   — sem ele o ML não devolve `refresh_token` e a conexão é recusada (`sem_offline_access`).
4. Copie o **Client ID** e o **Client Secret** para `ML_CLIENT_ID` e `ML_CLIENT_SECRET`. É a única
   configuração global do ML: cada empresa conecta as próprias contas em Configurações › Contas.

Fluxo de conexão: o admin clica em "Conectar conta" → `POST /api/ml_accounts/authorize` devolve a URL do ML
→ o ML chama `GET /auth/ml/callback`, que repassa `code`/`state` ao front → o front, logado, finaliza em
`POST /api/ml_accounts/connect`. O `state` só vale para o usuário que o criou (detalhes em DECISOES §5).

## Plano de ação com IA (OpenRouter)

Não existe chave nem modelo global de IA no ambiente: cada empresa configura a própria chave da
[OpenRouter](https://openrouter.ai/) e o próprio modelo (id no formato `fornecedor/modelo`, ex.:
`anthropic/claude-sonnet-4.5`) em **Configurações › Empresa**. Sem chave e modelo configurados, o
plano de ação (`POST /api/items/:id/ai-plan`) responde com um erro pedindo para configurar. A chave
nunca aparece em resposta, log ou mensagem de erro (fica cifrada no banco, `Active Record Encryption`);
a UI só recebe uma dica (`ai_key_hint`, os 4 últimos caracteres). Detalhes do contrato em DECISOES §10.

## Rodar localmente

Pré-requisito: Docker. Não é preciso Ruby na máquina.

```bash
cp .env.example .env                        # preencha ML_CLIENT_ID/SECRET
docker compose up -d                        # postgres + api (http://localhost:3100) + jobs (Solid Queue)
docker compose exec api bin/rails db:seed   # empresa demo com dados fictícios (opcional)
docker compose --profile web up -d          # também sobe o lunna-web (repo irmão em ../lunna-web) em :3101
```

Seed de desenvolvimento: `demo@lunna.dev` / `lunna12345` (admin) e `membro@lunna.dev` / `lunna12345`,
com uma conta ML fictícia e 60 dias de dados. A conta demo não tem tokens reais, então o worker
registra falhas de sincronização para ela; pare o serviço `jobs` se quiser o painel "verde".

O Postgres não expõe porta no host. Console: `docker compose exec api bin/rails console`.

## Variáveis de ambiente

Todas estão comentadas em [`.env.example`](.env.example).

| Variável | Uso |
|---|---|
| `API_URL` | Base pública da API; forma o `redirect_uri` do OAuth |
| `FRONT_URL` | Para onde o callback do ML devolve o usuário |
| `CORS_ORIGINS` | Origens do front (vírgula) |
| `API_HOST` | Produção: host aceito pelo Rails |
| `ML_CLIENT_ID`, `ML_CLIENT_SECRET` | App do Mercado Livre |
| `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_POOL` | Banco em dev/test |
| `DATABASE_URL` | Banco em produção |
| `SECRET_KEY_BASE`, `ACTIVE_RECORD_ENCRYPTION_*` | Produção; as chaves de criptografia protegem os tokens do ML |
| `RAILS_MAX_THREADS`, `JOB_CONCURRENCY`, `TRUSTED_PROXIES` | Ajustes de produção |

Segredos (`ML_CLIENT_SECRET`, tokens do ML, chave da OpenRouter de cada empresa) nunca vão para o
front, logs ou respostas. Tokens do ML e a chave da OpenRouter ficam criptografados no banco
(Active Record Encryption).

## Testes

Nenhum teste chama o Mercado Livre ou a OpenRouter de verdade (WebMock + fixtures em `spec/fixtures/ml/`).

```bash
docker compose run --rm -e RAILS_ENV=test api bash -c "bin/rails db:prepare && bundle exec rspec"
docker compose run --rm api bundle exec rubocop
docker compose run --rm api bin/brakeman --no-pager
```

## Deploy

Kubernetes (k3s) no padrão timeia/meustorytv: front em https://gestao.lunnashop.com.br e API em
https://api.lunnashop.com.br. Um comando builda as duas imagens, importa no servidor e aplica tudo:

```bash
VERSION=0.1.1 ./cd/prod/deploy.sh
```

Manifests, segredos, preparação do servidor e operação em [`cd/prod/README.md`](cd/prod/README.md).
