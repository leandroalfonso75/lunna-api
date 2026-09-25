# Kit de desenvolvimento do Lunna — design

Data: 2026-09-25 · Status: **aprovado** pelo dono. Revisado no mesmo dia: o kit vive **dentro dos repos existentes** (`lunna-api` e `lunna-web`), sem repositório novo.

## 1. Objetivo e sucesso

Dar a uma pessoa que **domina o Mercado Livre mas pouco desenvolvimento** um jeito seguro de criar funcionalidades novas no Lunna (`lunna-api` Rails + `lunna-web` Nuxt), usando o Claude Code.

Sucesso = ela descreve a funcionalidade em termos de ML e o fluxo a conduz por **ficha → testes → implementação → verificação → prints → PR**, sem conseguir quebrar por engano as regras de ouro (§4) e deixando ao dono só a revisão do PR.

## 2. Decisões já tomadas

| Tema | Decisão |
|---|---|
| Onde vive | **Dentro dos dois repos que já existem, sem repo novo.** O `lunna-api` é a base do kit (skills, scripts, guia, modelos): ele já orquestra o front (`docker compose --profile web`, `cd/prod/deploy.sh`). O `lunna-web` recebe só o seu `CLAUDE.md`. A pessoa abre o Claude Code em `lunna-api` e o front entra como pasta adicional (`../lunna-web`) |
| PR e prints (Bitbucket, sem Azure) | **Gera tudo, anexo manual**: scripts sobem o ambiente, tiram os prints numerados e montam o texto do PR; a pessoa abre o PR pelo link impresso e arrasta os prints na tela do Bitbucket. Sem credencial e sem imagem dentro do repo |
| Travas | **Só orientação**: nada bloqueia tecnicamente push na `main`, deploy ou segredos. A barreira é a revisão do PR pelo dono |
| Idioma | Todo o kit em português |
| Branches | Branch simples `feature/<nome>` nos dois repos para quem usa o kit (sem `git worktree`, para não confundir). O dono, que implementa o kit em si, usa worktree como de costume |
| Prints | Obrigatórios só em mudança visual |

## 3. Fora do escopo

Travas técnicas (hooks que bloqueiam), CI de servidor (Bitbucket Pipelines), deploy feito pela pessoa, Azure/work items, repositório novo, upload de imagem por API.

## 4. Regras de ouro (vão no `CLAUDE.md` do `lunna-api` e nos de cada stack)

1. **Somente leitura no Mercado Livre.** O único POST ao ML é `/oauth/token`. Nenhum `PUT/POST/DELETE` em `/items`, pedidos etc.
2. **Tudo escopado por empresa.** Toda leitura parte de `Current.company` → conta (`Current.account`). Nunca `MlItem.find` direto, nunca `company_id` vindo de parâmetro. Anúncio de outra empresa é 404.
3. **Regra de negócio só no back** (`app/services`). O front só exibe: layout, formatação e cores a partir de estados prontos.
4. **Parâmetros de negócio por empresa**, nunca fixos no código (imposto, margem, cortes da Curva ABC…).
5. **Segredos nunca** em código, log, resposta, print ou PR (`ML_CLIENT_SECRET`, tokens, chave da OpenRouter).
6. **Não inventar campos da API do ML.** Só endpoints e campos já documentados em `docs/SPEC.md §3`; um novo exige exemplo de resposta real salvo como fixture.
7. **Testes junto com o código** e verificação verde antes de qualquer PR.
8. **Peça ao dono** antes de: alterar `cd/prod/`, `.env*`, `docs/DECISOES.md`, migrations que apagam dados, dependências novas, ou qualquer coisa que faça deploy.

## 5. Estrutura de arquivos

```
lunna-api/                            # base do kit
├─ CLAUDE.md                          # regras de ouro + padrão do BACK + fluxo e ordem das skills (≤ 150 linhas)
├─ .claude/
│  ├─ settings.json                   # additionalDirectories: ../lunna-web (sem travas)
│  └─ skills/lunna-*/SKILL.md         # as 6 skills (§7)
├─ script/                            # scripts (§9); a pasta já existe vazia
│  ├─ setup.sh  dev-up.sh  dev-down.sh  nova-branch.sh
│  ├─ verificar.sh  prints.sh  pr.sh  testar-kit.sh
│  └─ prints/tirar-prints.mjs  prints/roteiros/base.json
├─ docs/
│  ├─ guia-operacao.html / .pdf       # guia para a pessoa (já existe em rascunho)
│  ├─ modelos/ficha-funcionalidade.md  modelos/pr.md
│  └─ superpowers/specs/…             # este spec
└─ evidencias/<branch>/               # saída local (logs, prints, PR.md); entra no .gitignore

lunna-web/
└─ CLAUDE.md                          # padrão do FRONT (≤ 150 linhas)
```

Como o `lunna-web` não é a pasta aberta no Claude Code, o `CLAUDE.md` do `lunna-api` manda ler `../lunna-web/CLAUDE.md` antes de mexer no front (§14 registra o teste do `@import`). Mudanças no próprio kit passam por PR no `lunna-api`, como qualquer outra.

## 6. Padrões de desenvolvimento

Cada `CLAUDE.md` tem: regras de ouro aplicáveis, mapa de pastas com um exemplo real de cada tipo de arquivo, "receitas" curtas e **o que exige teste** em cada tipo de mudança.

**Back (`lunna-api/CLAUDE.md`)**
- Camadas: controller fino (`render json:` com hashes de `Payloads`) → serviço `Dominio::Verbo` (`def self.call(...) = new(...).call`) → model. Erros como `{errors: [..]}` via `ErrorRendering`.
- Endpoint novo: rota em `config/routes.rb`, `include CurrentAccount` quando lê por conta, request spec + service spec.
- Cálculo novo: serviço com spec usando os **números do exemplo da ficha**.
- Chamada nova ao ML: método em `Ml::Client`, fixture em `spec/fixtures/ml/` com resposta real, WebMock; falha parcial vira nota na sincronização, nunca derruba a rodada.
- Migration: reversível, uuid como PK, FK com `on_delete: :cascade` quando pertencer à conta; atualizar `db/schema.rb`.
- Trabalho demorado em job (`app/jobs`, Solid Queue) com leitura por polling; nada longo dentro do request (exemplo: `Ai::ActionPlanJob`).
- Mensagens ao usuário em português; nenhum teste chama ML ou OpenRouter de verdade.

**Front (`lunna-web/CLAUDE.md`)**
- `app/lib/*Client.ts` (puro, recebe `$api`) → `app/composables` (estado) → `app/components`/`pages`. Nada de cálculo de negócio.
- Formatação só via `app/lib/format.ts`; cores só por tokens (`tokens.css`, tema claro e escuro); estados `ok/warn/bad` vêm prontos da API.
- Teste Vitest ao lado do código (`*.test.ts`); lógica assíncrona em módulo puro testável com timers falsos (exemplo: `aiPlanRunner`).
- Toda tela nova: claro, escuro e 360 px; print obrigatório.
- Polling (não SSE/WebSocket) para qualquer coisa demorada.

## 7. Skills (`lunna-api/.claude/skills/lunna-*/SKILL.md`, ≤ 150 linhas cada)

| Skill | Quando dispara | O que faz |
|---|---|---|
| `lunna-nova-funcionalidade` | "quero uma tela/alerta/métrica…" | Entrevista com a **ficha da funcionalidade** (§8), confere com as regras de ouro, cria a branch (`nova-branch.sh`), escreve **testes primeiro**, implementa back e front, roda `lunna-verificar`, `lunna-prints`, `lunna-pr` |
| `lunna-api-mercado-livre` | dúvida sobre dado/endpoint do ML | Mapa dos 14 endpoints já usados (`docs/SPEC.md §3`); como propor um novo (somente GET, fixture real, permissão do DevCenter) |
| `lunna-verificar` | antes de PR, ou "está tudo certo?" | Roda `script/verificar.sh`, traduz falhas em português e corrige |
| `lunna-prints` | mudança visual | Roda `script/prints.sh` com o roteiro da funcionalidade e confere cada print (sem dados sensíveis) |
| `lunna-pr` | "abrir PR" | Roda `script/pr.sh`, preenche o texto sem placeholders e explica como anexar os prints |
| `lunna-corrigir-bug` | "está errado/quebrou" | Reproduz com teste que falha, corrige a causa raiz, verifica |

## 8. Ficha da funcionalidade (`docs/modelos/ficha-funcionalidade.md`)

Escrita em termos de ML pela pessoa (a skill entrevista e preenche):
1. **O que você quer ver** (tela, tabela, alerta) e por quê (decisão que ajuda a tomar).
2. **De onde vem o dado** (campo do ML, se souber; senão a skill procura em `SPEC.md §3`).
3. **Como calcular**, com **um exemplo numérico** (entrada → resultado esperado), incluindo casos que **não** entram. Vira o teste.
4. **Quem vê** (admin, membro, ambos).
5. **Critério de aceite**: lista "dado X ⇒ aparece Y".
6. **O que NÃO muda** (para não estragar o que já funciona).

## 9. Scripts (bash, Docker; sem Ruby na máquina; rodam a partir da raiz do `lunna-api`)

Todos: `set -euo pipefail`, mensagens em português, `--ajuda`, idempotentes, código de saída ≠ 0 em falha e a próxima ação sugerida na mensagem. Nomes distintos dos `bin/` do Rails (o `bin/setup` do Rails continua existindo e é outro).

| Script | Faz | Saída |
|---|---|---|
| `script/setup.sh` | Confere Docker, Compose, Node 22 (nvm), git, Chrome; clona o `lunna-web` ao lado (SSH Bitbucket) se faltar; cria o `.env` do back; `npm ci` no front | Checklist ✔/✘ |
| `script/dev-up.sh [--com-jobs]` | Sobe Postgres + API (:3100) e front (:3101, `npm run dev` com recarga automática), roda o seed demo, espera `/up` | URLs e login demo (`demo@lunna.dev` / `lunna12345`). Sem `--com-jobs` o worker fica parado (a conta demo não tem token e geraria falhas de sincronização) |
| `script/dev-down.sh` | Para tudo | — |
| `script/nova-branch.sh <nome>` | `feature/<slug>` a partir da `main` atualizada nos dois repos; recusa se houver alteração pendente | Branch criada |
| `script/verificar.sh [api\|web\|tudo]` | API: `rspec`, `rubocop`, `brakeman`, `bundler-audit`. Web: `typecheck`, `lint`, `vitest`. Log completo em `evidencias/<branch>/verificacao-<data>.txt` | Resumo ✔/✘ em português; exit 1 se algo falhar |
| `script/prints.sh [roteiro.json]` | Confere o dono real da porta (`/proc/<pid>/cwd`), sobe **build de produção** do front na :3101 (porta liberada na `CORS_ORIGINS` da API), faz login demo, tira prints numerados via Playwright no Chrome instalado. Se a :3101 estiver com o `npm run dev` do próprio `lunna-web` (dono conferido), encerra esse processo e o sobe de novo ao final | `evidencias/<branch>/prints/NN-<slug>-<claro\|escuro\|mobile>.png` |
| `script/pr.sh` | Monta `evidencias/<branch>/PR.md` (resumo em linguagem de negócio, o que mudou por repo, como testar, evidências com legenda, resultado da verificação, checklist das regras de ouro) e imprime o link `pull-requests/new?source=<branch>` de cada repo alterado | `PR.md` sem placeholders |
| `script/testar-kit.sh` | Teste do próprio kit: sintaxe dos scripts (`bash -n`, `shellcheck` se houver), `--ajuda` de cada um, e confere que todo caminho citado nos `CLAUDE.md`/skills existe | ✔/✘ |

**Roteiro de prints** (`script/prints/roteiros/base.json`): lista de cenas `{ nome, rota, esperar, acoes?, viewport, tema }`. O base cobre login, visão geral, anúncios, Curva ABC e configurações. Cada funcionalidade acrescenta o seu roteiro em `evidencias/<branch>/roteiro.json`.

## 10. Fluxo ponta a ponta

```
script/setup.sh (uma vez) → abrir o Claude Code na pasta lunna-api
→ /lunna-nova-funcionalidade  (ficha → branch → testes → código)
→ /lunna-verificar            (tudo verde)
→ /lunna-prints               (se visual)
→ /lunna-pr                   (PR.md + links)
→ pessoa: git push, abre o PR pelo link, cola PR.md, arrasta os prints
→ dono revisa e faz o merge e o deploy
```

Funcionalidade que toca back e front gera **dois PRs**, um em cada repo, com o mesmo `PR.md` dividido por repo.

## 11. Erros e casos de borda

- Porta 3100/3101 ocupada por outro projeto: aborta e diz quem é o dono (`/proc/<pid>/cwd`); nunca reaproveita silenciosamente (já serviu build errado).
- Docker sem redes livres: o compose usa a subnet fixa `10.201.0.0/24`; a mensagem explica que não se deve podar redes de outros projetos.
- `docker build` sem `--network host` falha no DNS desta máquina: só relevante ao deploy (fica com o dono).
- Teste falhando: `verificar.sh` mostra o teste e o arquivo, e a skill corrige pelo padrão dos `CLAUDE.md`; falha de spec gerado por agente costuma ser bug do spec, não do código.
- Chrome ausente: `prints.sh` explica como instalar; não tenta baixar navegador.

## 12. Validação do kit

`script/testar-kit.sh` verde e um **exercício de ponta a ponta** numa mudança trivial (ex.: rótulo novo no front) executado por `lunna-nova-funcionalidade` até o `PR.md` e os prints, **sem push**. Critérios de aceite:

1. `setup.sh` + `dev-up.sh` deixam a aplicação no ar com o login demo.
2. `verificar.sh tudo` verde na `main`; **quebrar de propósito** um teste faz o script sair com 1 e mensagem clara.
3. `prints.sh` gera os prints base e **recusa** porta ocupada por outro projeto.
4. `pr.sh` gera `PR.md` sem placeholders e imprime os links.
5. Cada skill carrega no Claude Code aberto em `lunna-api` (`/lunna-…`) e tem ≤ 150 linhas; cada `CLAUDE.md` ≤ 150 linhas.
6. Com o Claude Code aberto em `lunna-api`, ele lê o `CLAUDE.md` do front e consegue editar arquivos em `../lunna-web`.
7. Nenhum segredo nos arquivos do kit, nos prints do roteiro base nem no `PR.md` gerado.

## 13. Fases

Implementação em branch `feature/kit-desenvolvimento` de cada repo (worktrees do dono), com PR por repo.

1. `CLAUDE.md` (back e front), `.claude/settings.json`, ficha e modelo de PR, `setup`, `dev-up/down`, `nova-branch`, `verificar`, `testar-kit`.
2. As 6 skills.
3. `prints` e `pr`, o exercício de ponta a ponta e o **guia de operação em PDF** atualizado com a saída real dos scripts.

## 14. Pontos em aberto (baixo risco, resolvidos na implementação)

- Se o Bitbucket do workspace oferece PR como rascunho; senão o `PR.md` sugere o prefixo `[WIP]` no título.
- O README do `lunna-api` ainda diz "leitura e escrita + `offline_access`"; a tela atual do DevCenter usa o fluxo **Refresh Token** e permissões em **Leitura**. O kit corrige esse trecho e documenta o passo a passo do DevCenter para o dono.
- Restrição de branch no Bitbucket (bloquear push direto na `main`, exigir aprovação), se o plano permitir: recomendada como barreira sem código.
- Testar na implementação se `@../lunna-web/CLAUDE.md` (import) e `permissions.additionalDirectories` funcionam como esperado nesta versão do Claude Code; se não, vale a instrução explícita de leitura já prevista em §5.
