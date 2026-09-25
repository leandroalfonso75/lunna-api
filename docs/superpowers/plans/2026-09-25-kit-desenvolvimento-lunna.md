# Kit de desenvolvimento do Lunna — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar o kit que permite a uma pessoa que domina o Mercado Livre, mas pouco desenvolvimento, criar funcionalidades novas no Lunna com segurança: `CLAUDE.md` de padrão (back e front), 6 skills, 8 scripts, modelos de ficha e PR e o guia de operação em PDF.

**Architecture:** Tudo dentro dos repos existentes. O `lunna-api` é a base (`script/`, `.claude/skills/`, `docs/`, `CLAUDE.md`); o `lunna-web` recebe só o `CLAUDE.md`. Scripts em bash (Docker, sem Ruby na máquina) com uma biblioteca comum (`script/lib/comum.sh`) e testes próprios (`script/testes/*_test.sh`) executados por `script/testar-kit.sh`. Prints com `playwright-core` no Chrome instalado; texto do PR montado por script a partir de um modelo, com anexo manual das imagens no Bitbucket.

**Tech Stack:** bash, Docker Compose, Node 22 (nvm) + `playwright-core`, Google Chrome, perl (slug e modelo do PR), Markdown (skills e `CLAUDE.md`), HTML→PDF pelo Chrome.

**Spec:** `docs/superpowers/specs/2026-09-25-kit-desenvolvimento-lunna-design.md` (o executor lê o spec junto com este plano).

## Global Constraints

- Scripts em `script/*.sh`, bash com `set -euo pipefail`, **mensagens em português**, `--ajuda`, idempotentes, código de saída ≠ 0 em falha **com a próxima ação sugerida**. Rodam a partir da raiz do `lunna-api`, via Docker, **sem Ruby na máquina**.
- Nomes distintos dos `bin/` do Rails (o `bin/setup` do Rails continua existindo e é outro).
- Cada `SKILL.md` ≤ 150 linhas; cada `CLAUDE.md` ≤ 150 linhas.
- Nenhum segredo nos arquivos do kit, nos prints do roteiro base nem no `PR.md` gerado.
- Prints em `evidencias/<branch>/prints/NN-<slug>-<claro|escuro|mobile>.png`; **build de produção** do front na porta **3101** (a única liberada na `CORS_ORIGINS` da API); conferir o dono real da porta (`/proc/<pid>/cwd`) antes de usar.
- **Só orientação**: nenhum hook nem bloqueio técnico.
- Node 22 para o front (o Node 24 bloqueia scripts de instalação); a suíte do back roda por `docker compose run --rm -T -e RAILS_ENV=test api …`.
- Implementação na branch `feature/kit-desenvolvimento` de cada repo, em worktrees. **Não fazer push nem abrir PR** sem o dono pedir. Commits em português com as duas linhas de atribuição:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH
  ```

**Ambiente do executor** (worktrees; nos checkouts normais o `WEB_DIR` não é necessário):

```bash
export API=~/workspace/.worktrees/lunna-api-kit        # branch feature/kit-desenvolvimento (já existe)
export WEB=~/workspace/.worktrees/lunna-web-kit        # criado na Tarefa 2
export WEB_DIR="$WEB"                                   # os scripts procuram o front aqui
cd "$API"
```

## Review Focus

1. **Porta 3100/3101 ocupada por outro projeto** — recusa e diz o dono; nunca reaproveita (testes das Tarefas 2 e 5).
2. **`nova-branch.sh` com alteração pendente, branch já existente, nome com acento/símbolos ou sem nome** — recusa com mensagem; o slug tira acento (teste da Tarefa 3).
3. **Falha real virando "verde"** (Docker indisponível, `tee` engolindo o status) e **suíte quebrada de propósito** — `verificar.sh` sai com 1 (testes da Tarefa 4).
4. **Seletor do roteiro que nunca aparece** ou login demo ausente — o print não é salvo em branco; o script falha com o nome da cena (Tarefa 5).
5. **PR na `main`, sem resumo, sem verificação verde, com mudança visual sem prints, ou com `{{` sobrando** — `pr.sh` recusa; o `PR.md` nunca sai com placeholders (Tarefa 6).

---

## Estrutura de arquivos

| Arquivo | Repo | Responsabilidade |
|---|---|---|
| `script/lib/comum.sh` | api | Cores/mensagens, raízes, slug, dono da porta, Node 22, compose, evidências, link de PR |
| `script/testar-kit.sh` | api | Testa o próprio kit (sintaxe, `--ajuda`, testes, limites, caminhos citados) |
| `script/testes/*_test.sh`, `*_lento_test.sh` | api | Testes rápidos e lentos (Docker/navegador) de cada script |
| `script/setup.sh` `dev-up.sh` `dev-down.sh` | api | Ambiente local |
| `script/nova-branch.sh` | api | Branch `feature/<nome>` nos dois repos |
| `script/verificar.sh` | api | Testes + estilo + segurança dos dois repos, com log e resumo |
| `script/prints.sh` + `script/prints/{package.json,tirar-prints.mjs,roteiros/base.json}` | api | Prints numerados |
| `script/pr.sh` | api | `PR.md` e links de PR |
| `docs/modelos/{ficha-funcionalidade,pr}.md` | api | Modelos usados pelas skills e por `pr.sh` |
| `CLAUDE.md`, `.claude/settings.json` | api | Regras de ouro, padrão do back, fluxo; diretório adicional do front |
| `.claude/skills/lunna-*/SKILL.md` (6) | api | Skills |
| `CLAUDE.md` | web | Padrão do front |
| `README.md`, `docs/guia-operacao.{html,pdf}` | api | Correção do DevCenter e guia final |

**Ordem das tarefas.** Difere das fases do spec (§13) porque `testar-kit.sh` confere que `CLAUDE.md` e skills só citam caminhos que existem: os documentos vêm depois dos scripts que citam. Cada tarefa termina com um commit; nenhuma exige a seguinte.

---

### Task 1: Biblioteca comum e `testar-kit.sh`

**Files:**
- Create: `script/lib/comum.sh`, `script/testes/comum_test.sh`, `script/testar-kit.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces (em `comum.sh`, usadas por todas as tarefas seguintes): variáveis `RAIZ_KIT` (lunna-api dos scripts), `RAIZ_API` (`$LUNNA_API_DIR` ou `RAIZ_KIT`), `RAIZ_WEB` (`$WEB_DIR` ou `$RAIZ_API/../lunna-web`); funções `ok`, `falha`, `aviso`, `passo`, `morrer "msg" ["próximo passo"]`, `tratar_ajuda "texto" "$@"`, `slug_de "texto"`, `dono_da_porta PORTA` (imprime `PID<TAB>DIRETÓRIO`), `porta_em_uso PORTA`, `com_node22 comando…`.

- [ ] **Step 1: Escrever o teste que falha**

Criar `script/testes/comum_test.sh`:

```bash
#!/usr/bin/env bash
# Testes de script/lib/comum.sh. Rápido: não usa Docker nem rede.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/comum.sh
source "$DIR/../lib/comum.sh"

FALHAS=0
esperar() { # esperar "descrição" "esperado" "obtido"
  if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi
}

# --- slug_de ---
esperar "slug tira acento e símbolo" "alerta-de-preco-acima" "$(slug_de 'Alerta de Preço acima!')"
esperar "slug de nome já limpo não muda" "meu-alerta" "$(slug_de 'meu-alerta')"
esperar "slug colapsa espaços e bordas" "a-b" "$(slug_de '  a   b  ')"
esperar "slug de só símbolos fica vazio" "" "$(slug_de '!!!')"

# --- morrer / tratar_ajuda ---
saida="$( (morrer "deu ruim" "faça isso") 2>&1 )"; st=$?
esperar "morrer sai com 1" "1" "$st"
case "$saida" in *"Próximo passo: faça isso"*) ok "morrer mostra o próximo passo" ;; *) falha "morrer sem próximo passo: $saida"; FALHAS=$((FALHAS+1)) ;; esac
saida="$(tratar_ajuda "texto de ajuda" --ajuda)"; st=$?
esperar "--ajuda imprime e sai 0" "texto de ajuda|0" "$saida|$st"
saida="$(tratar_ajuda "texto de ajuda" outra-coisa)"
esperar "sem --ajuda não imprime nada" "" "$saida"

# --- dono_da_porta / porta_em_uso (servidor http de verdade numa pasta temporária) ---
if command -v python3 >/dev/null 2>&1; then
  TMP="$(mktemp -d)"; REAL="$(cd "$TMP" && pwd -P)"
  ( cd "$TMP" && exec python3 -u -m http.server 0 --bind 127.0.0.1 >"$TMP/saida.txt" 2>&1 ) &
  SERVIDOR=$!
  PORTA=""
  for _ in $(seq 1 30); do
    PORTA="$(grep -oE 'port [0-9]+' "$TMP/saida.txt" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)"
    [ -n "$PORTA" ] && break; sleep 0.2
  done
  if [ -z "$PORTA" ]; then falha "não consegui subir o servidor de teste"; FALHAS=$((FALHAS+1))
  else
    dono="$(dono_da_porta "$PORTA")"
    esperar "dono da porta é o processo e a pasta certos" "$SERVIDOR"$'\t'"$REAL" "$dono"
    if porta_em_uso "$PORTA"; then ok "porta_em_uso vê a porta ocupada"; else falha "porta_em_uso não viu"; FALHAS=$((FALHAS+1)); fi
    kill "$SERVIDOR" 2>/dev/null; wait "$SERVIDOR" 2>/dev/null
    if porta_em_uso "$PORTA"; then falha "porta continua ocupada"; FALHAS=$((FALHAS+1)); else ok "porta livre depois de encerrar"; fi
  fi
  rm -rf "$TMP"
else
  aviso "python3 ausente: testes de porta pulados"
fi

[ "$FALHAS" -eq 0 ]
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash script/testes/comum_test.sh`
Expected: FAIL — `script/lib/comum.sh: No such file or directory`.

- [ ] **Step 3: Implementar `script/lib/comum.sh`**

```bash
#!/usr/bin/env bash
# Funções compartilhadas pelos scripts do kit. Não é executável: cada script faz
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"
# Regras do kit: mensagens em português, saída ≠ 0 em falha e a próxima ação sugerida.

# RAIZ_KIT: o lunna-api onde estes scripts moram. RAIZ_API: o projeto-alvo (o mesmo, salvo nos
# testes, que apontam LUNNA_API_DIR para clones temporários). RAIZ_WEB: o lunna-web ao lado (ou WEB_DIR).
RAIZ_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAIZ_API="${LUNNA_API_DIR:-$RAIZ_KIT}"
RAIZ_WEB="${WEB_DIR:-$RAIZ_API/../lunna-web}"

if [ -t 1 ]; then
  VERDE=$'\033[32m'; VERMELHO=$'\033[31m'; AMARELO=$'\033[33m'; NEGRITO=$'\033[1m'; RESET=$'\033[0m'
else
  VERDE=""; VERMELHO=""; AMARELO=""; NEGRITO=""; RESET=""
fi

ok()    { printf '%s✔%s %s\n' "$VERDE" "$RESET" "$*"; }
falha() { printf '%s✘%s %s\n' "$VERMELHO" "$RESET" "$*"; }
aviso() { printf '%s!%s %s\n' "$AMARELO" "$RESET" "$*"; }
passo() { printf '\n%s==> %s%s\n' "$NEGRITO" "$*" "$RESET"; }

# morrer "mensagem" ["próximo passo"] — imprime ✘, sugere o que fazer e sai com 1.
morrer() {
  falha "$1"
  if [ -n "${2:-}" ]; then printf '   Próximo passo: %s\n' "$2"; fi
  exit 1
}

# tratar_ajuda "texto" "$@" — imprime o texto e sai com 0 quando pedirem --ajuda ou -h.
tratar_ajuda() {
  local texto="$1" arg; shift
  for arg in "$@"; do
    case "$arg" in --ajuda|-h) printf '%s\n' "$texto"; exit 0 ;; esac
  done
  return 0
}

# slug_de "Alerta de Preço!" → alerta-de-preco   (perl vem com Linux e macOS)
slug_de() {
  printf '%s' "$1" | perl -CSD -MUnicode::Normalize -ne '
    $_ = NFD($_); s/\p{Mn}//g; $_ = lc $_; s/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; print;'
}

# dono_da_porta PORTA — imprime "PID<TAB>DIRETÓRIO" do processo que escuta na porta (nada se livre).
dono_da_porta() {
  local porta="$1" pid dir
  if command -v ss >/dev/null 2>&1; then
    pid="$(ss -ltnpH "sport = :$porta" 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2 || true)"
  else
    pid="$(lsof -nP -iTCP:"$porta" -sTCP:LISTEN -Fp 2>/dev/null | sed -n 's/^p//p' | head -1 || true)"
  fi
  [ -n "$pid" ] || return 0
  if [ -r "/proc/$pid/cwd" ]; then
    dir="$(readlink "/proc/$pid/cwd")"
  else
    dir="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  fi
  printf '%s\t%s\n' "$pid" "${dir:-?}"
}

# porta_em_uso PORTA — sucesso se algum processo escuta nela.
porta_em_uso() { [ -n "$(dono_da_porta "$1")" ]; }

# com_node22 comando… — roda com o Node 22 do nvm no PATH.
com_node22() {
  local pasta
  pasta="$(ls -d "$HOME"/.nvm/versions/node/v22.* 2>/dev/null | sort -V | tail -1)"
  [ -n "$pasta" ] || morrer "Node 22 não encontrado (nvm)." "instale com: nvm install 22"
  PATH="$pasta/bin:$PATH" "$@"
}
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `bash script/testes/comum_test.sh`
Expected: todas as linhas com `✔` e código de saída 0 (`echo $?` → `0`).

- [ ] **Step 5: Escrever `script/testar-kit.sh`**

```bash
#!/usr/bin/env bash
# Testa o próprio kit. Rápido por padrão; --completo inclui os testes lentos (Docker, navegador).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/testar-kit.sh [--completo]
Confere o kit: sintaxe dos scripts, --ajuda de cada um, testes dos scripts (script/testes/*_test.sh),
tamanho dos guias e das skills e se os caminhos citados neles existem.
  --completo   inclui os testes lentos (script/testes/*_lento_test.sh: Docker e navegador; vários minutos)."
tratar_ajuda "$AJUDA" "$@"
COMPLETO=0
if [ "${1:-}" = "--completo" ]; then COMPLETO=1; fi

FALHAS=0
checar() { # checar "descrição" comando…
  local descricao="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$descricao"; else falha "$descricao"; FALHAS=$((FALHAS+1)); fi
}
limite() { # limite arquivo máximo-de-linhas
  local n; n="$(wc -l < "$1")"
  if [ "$n" -le "$2" ]; then ok "$1: $n linhas (máx. $2)"; else falha "$1: $n linhas (máx. $2)"; FALHAS=$((FALHAS+1)); fi
}
# conferir_caminhos arquivo base — todo `caminho/citado` entre crases que pareça caminho do projeto precisa existir.
conferir_caminhos() {
  local arquivo="$1" base="$2" trecho alvo faltou=0
  while IFS= read -r trecho; do
    case "$trecho" in *'*'*|*'<'*|*'{'*|*' '*|*'$'*|*'|'*) continue ;; esac
    case "$trecho" in
      app/*|spec/*|script/*|docs/*|config/*|db/*|lib/*|cd/*|.claude/*|../lunna-web/*) ;;
      *) continue ;;
    esac
    case "$trecho" in ../lunna-web/*) alvo="$RAIZ_WEB/${trecho#../lunna-web/}" ;; *) alvo="$base/$trecho" ;; esac
    if [ ! -e "$alvo" ]; then falha "$arquivo cita '$trecho', que não existe"; faltou=1; fi
  done < <(grep -oE '`[^` ]+`' "$arquivo" | tr -d '`' | sort -u)
  if [ "$faltou" -eq 0 ]; then ok "caminhos citados em $arquivo existem"; else FALHAS=$((FALHAS+1)); fi
}

cd "$RAIZ_KIT"
SCRIPTS=(); for f in script/*.sh; do if [ -e "$f" ]; then SCRIPTS+=("$f"); fi; done
TODOS=("${SCRIPTS[@]}"); for f in script/lib/*.sh script/testes/*.sh; do if [ -e "$f" ]; then TODOS+=("$f"); fi; done

passo "Sintaxe dos scripts"
for f in "${TODOS[@]}"; do checar "sintaxe: $f" bash -n "$f"; done
if command -v shellcheck >/dev/null 2>&1; then
  for f in "${TODOS[@]}"; do checar "shellcheck: $f" shellcheck -x -S error "$f"; done
else
  aviso "shellcheck não instalado (opcional)"
fi

passo "--ajuda de cada script"
for f in "${SCRIPTS[@]}"; do checar "--ajuda: $f" bash -c "bash '$f' --ajuda | grep -q '^Uso:'"; done

passo "Testes dos scripts"
for t in script/testes/*_test.sh; do
  if [ -e "$t" ]; then
    case "$t" in *_lento_test.sh) if [ "$COMPLETO" -eq 0 ]; then continue; fi ;; esac
    if bash "$t"; then ok "$t"; else falha "$t"; FALHAS=$((FALHAS+1)); fi
  fi
done

passo "Guias e skills"
if [ -f CLAUDE.md ]; then limite CLAUDE.md 150; conferir_caminhos CLAUDE.md "$RAIZ_KIT"; fi
if [ -f "$RAIZ_WEB/CLAUDE.md" ]; then limite "$RAIZ_WEB/CLAUDE.md" 150; conferir_caminhos "$RAIZ_WEB/CLAUDE.md" "$RAIZ_WEB"; fi
for s in .claude/skills/*/SKILL.md; do
  if [ -e "$s" ]; then
    limite "$s" 150
    checar "$s tem name e description" bash -c "head -1 '$s' | grep -q '^---$' && grep -q '^name: ' '$s' && grep -q '^description: ' '$s'"
    conferir_caminhos "$s" "$RAIZ_KIT"
  fi
done

echo
if [ "$FALHAS" -eq 0 ]; then ok "Kit em ordem."; else morrer "$FALHAS verificação(ões) do kit falharam." "corrija os itens ✘ acima e rode ./script/testar-kit.sh de novo"; fi
```

- [ ] **Step 6: Rodar `testar-kit.sh`, ajustar o `.gitignore` e commitar**

```bash
chmod +x script/testar-kit.sh script/testes/comum_test.sh
printf '\n# Kit de desenvolvimento (saída local dos scripts)\n/evidencias/\n/script/prints/node_modules/\n' >> .gitignore
./script/testar-kit.sh
```
Expected: `✔ Kit em ordem.` (ainda há poucos scripts; `--ajuda` só de `testar-kit.sh`).

```bash
git add script .gitignore
git commit -m "feat: base do kit — biblioteca comum e testar-kit.sh

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 2: Ambiente local — `setup.sh`, `dev-up.sh`, `dev-down.sh`

**Files:**
- Create: `script/setup.sh`, `script/dev-up.sh`, `script/dev-down.sh`, `script/testes/setup_test.sh`, `script/testes/dev_lento_test.sh`
- Modify: `script/lib/comum.sh` (acrescentar funções)

**Interfaces:**
- Consumes (Tarefa 1): `RAIZ_API`, `RAIZ_WEB`, `ok`, `falha`, `aviso`, `passo`, `morrer`, `tratar_ajuda`, `dono_da_porta`, `porta_em_uso`, `com_node22`.
- Produces (em `comum.sh`, usadas nas Tarefas 3-6): `compose …` (docker compose do lunna-api de qualquer pasta), `esperar_url URL [SEGUNDOS]`, `slug_da_branch [REPO]`, `pasta_evidencias`, `estado_da_porta_api` e `estado_da_porta_web` (imprimem `livre`, `nosso` ou `outro:<dir> (processo <pid>)`), `subir_front_dev`, `desligar_front_da_porta`.

- [ ] **Step 1: Preparar o worktree do front e as dependências dele**

```bash
git -C ~/workspace/lunna/lunna-web worktree add ~/workspace/.worktrees/lunna-web-kit -b feature/kit-desenvolvimento main
(cd "$WEB" && PATH="$(ls -d ~/.nvm/versions/node/v22.* | sort -V | tail -1)/bin:$PATH" npm ci --no-audit --no-fund)
```
Expected: worktree criado e `node_modules` instalado em `$WEB`.

- [ ] **Step 2: Escrever os testes que falham**

`script/testes/setup_test.sh`:

```bash
#!/usr/bin/env bash
# Testes de setup.sh. Rápido; --so-verificar não baixa nem instala nada.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

saida="$(bash "$DIR/../setup.sh" --ajuda)"; st=$?
esperar "--ajuda sai 0" "0" "$st"; contem "--ajuda começa com Uso:" "$saida" "Uso: script/setup.sh"

# Nesta máquina de desenvolvimento os requisitos existem: --so-verificar precisa dar 0.
saida="$(bash "$DIR/../setup.sh" --so-verificar 2>&1)"; st=$?
esperar "requisitos atendidos: exit 0" "0" "$st"; contem "mostra o Docker" "$saida" "Docker funcionando"

# Docker quebrado (falso) precisa virar ✘ com "Como resolver" e exit 1.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '#!/bin/sh\nexit 1\n' > "$TMP/docker"; chmod +x "$TMP/docker"
saida="$(PATH="$TMP:$PATH" bash "$DIR/../setup.sh" --so-verificar 2>&1)"; st=$?
esperar "sem Docker: exit 1" "1" "$st"
contem "sem Docker: diz como resolver" "$saida" "Como resolver"

[ "$FALHAS" -eq 0 ]
```

`script/testes/dev_lento_test.sh`:

```bash
#!/usr/bin/env bash
# Teste lento (Docker + front). Só roda com ./script/testar-kit.sh --completo.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

for p in 3100 3101; do
  if porta_em_uso "$p"; then aviso "porta $p ocupada; teste lento de dev-up pulado (rode dev-down.sh antes)"; exit 0; fi
done

# 1) Porta 3101 de outro projeto: dev-up recusa e diz a pasta do dono.
TMP="$(mktemp -d)"; REAL="$(cd "$TMP" && pwd -P)"
( cd "$TMP" && exec python3 -m http.server 3101 --bind 127.0.0.1 >/dev/null 2>&1 ) &
SERVIDOR=$!; sleep 1
saida="$(bash "$DIR/../dev-up.sh" 2>&1)"; st=$?
esperar "porta 3101 alheia: exit 1" "1" "$st"
contem "porta 3101 alheia: cita 'outro projeto'" "$saida" "outro projeto"
contem "porta 3101 alheia: mostra a pasta do dono" "$saida" "$REAL"
kill "$SERVIDOR" 2>/dev/null; wait "$SERVIDOR" 2>/dev/null; rm -rf "$TMP"

# 2) Sobe de verdade, duas vezes (idempotente), confere e desliga.
bash "$DIR/../dev-up.sh" >/dev/null 2>&1; esperar "dev-up: exit 0" "0" "$?"
esperar "API responde /up" "200" "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3100/up)"
esperar "front responde /api/saude" "200" "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3101/api/saude)"
bash "$DIR/../dev-up.sh" >/dev/null 2>&1; esperar "dev-up de novo (idempotente): exit 0" "0" "$?"
bash "$DIR/../dev-down.sh" >/dev/null 2>&1; esperar "dev-down: exit 0" "0" "$?"
if porta_em_uso 3101; then falha "3101 continua ocupada"; FALHAS=$((FALHAS+1)); else ok "3101 livre depois do dev-down"; fi

[ "$FALHAS" -eq 0 ]
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `bash script/testes/setup_test.sh`
Expected: FAIL (`script/setup.sh: No such file`).

- [ ] **Step 4: Acrescentar as funções ao fim de `script/lib/comum.sh`**

```bash

# compose … — docker compose do lunna-api, de qualquer pasta.
compose() { docker compose --project-directory "$RAIZ_API" -f "$RAIZ_API/docker-compose.yml" "$@"; }

# esperar_url URL [SEGUNDOS] — espera a URL responder 2xx (padrão 60 s). Falha se estourar o tempo.
esperar_url() {
  local url="$1" limite="${2:-60}" gasto=0
  until curl -fsS -o /dev/null --max-time 3 "$url" 2>/dev/null; do
    gasto=$((gasto + 3))
    if [ "$gasto" -ge "$limite" ]; then return 1; fi
    sleep 3
  done
}

# slug_da_branch [REPO] — branch atual com "/" trocado por "-" (feature/x → feature-x).
slug_da_branch() {
  local branch
  branch="$(git -C "${1:-$RAIZ_API}" branch --show-current 2>/dev/null || true)"
  printf '%s' "${branch:-sem-branch}" | tr '/' '-'
}

# pasta_evidencias — evidencias/<branch>/ do projeto-alvo (criada se faltar).
pasta_evidencias() {
  local pasta; pasta="$RAIZ_API/evidencias/$(slug_da_branch)"
  mkdir -p "$pasta"; printf '%s' "$pasta"
}

# estado_da_porta_api — "livre", "nosso" (compose deste projeto no ar) ou "outro:<dir> (processo <pid>)".
estado_da_porta_api() {
  local dono
  if [ -n "$(compose ps -q --status running api 2>/dev/null)" ]; then printf 'nosso'; return 0; fi
  dono="$(dono_da_porta 3100)"
  if [ -z "$dono" ]; then printf 'livre'; else printf 'outro:%s (processo %s)' "${dono#*$'\t'}" "${dono%%$'\t'*}"; fi
}

# estado_da_porta_web — "livre", "nosso" (dono é o lunna-web deste projeto) ou "outro:<dir> (processo <pid>)".
estado_da_porta_web() {
  local dono dir web
  dono="$(dono_da_porta 3101)"
  if [ -z "$dono" ]; then printf 'livre'; return 0; fi
  dir="${dono#*$'\t'}"; web="$(cd "$RAIZ_WEB" 2>/dev/null && pwd -P || true)"
  if [ -n "$web" ] && [ "$dir" = "$web" ]; then printf 'nosso'; else printf 'outro:%s (processo %s)' "$dir" "${dono%%$'\t'*}"; fi
}

# subir_front_dev — npm run dev do lunna-web na :3101, em segundo plano (log em evidencias/dev-web.log).
subir_front_dev() {
  mkdir -p "$RAIZ_API/evidencias"
  ( cd "$RAIZ_WEB" && NUXT_PUBLIC_API_URL=http://localhost:3100 com_node22 nohup npm run dev \
      >"$RAIZ_API/evidencias/dev-web.log" 2>&1 & )
}

# desligar_front_da_porta — encerra o processo da :3101 (chame só depois de conferir que é o nosso).
desligar_front_da_porta() {
  local dono; dono="$(dono_da_porta 3101)"
  if [ -z "$dono" ]; then return 0; fi
  kill "${dono%%$'\t'*}" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! porta_em_uso 3101; then return 0; fi
    sleep 1
  done
}
```

- [ ] **Step 5: Escrever `script/setup.sh`**

```bash
#!/usr/bin/env bash
# Prepara a máquina para desenvolver no Lunna. Pode rodar de novo sem estragar nada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/setup.sh [--so-verificar]
Confere Docker, Docker Compose, git, Node 22 (nvm), Chrome e o acesso ao Bitbucket; baixa o lunna-web ao
lado do lunna-api; cria o .env do back; instala as dependências do front e do script de prints.
  --so-verificar   só confere os requisitos, sem baixar nem instalar nada."
tratar_ajuda "$AJUDA" "$@"
SO_VERIFICAR=0
if [ "${1:-}" = "--so-verificar" ]; then SO_VERIFICAR=1; fi

PENDENCIAS=0
requisito() { # requisito "nome" "como resolver" comando…
  local nome="$1" dica="$2"; shift 2
  if "$@" >/dev/null 2>&1; then ok "$nome"
  else falha "$nome"; printf '   Como resolver: %s\n' "$dica"; PENDENCIAS=$((PENDENCIAS + 1)); fi
}

passo "Requisitos"
requisito "Docker funcionando" "instale o Docker e deixe-o aberto (o comando 'docker info' precisa responder)" docker info
requisito "Docker Compose" "atualize o Docker (o comando 'docker compose version' precisa responder)" docker compose version
requisito "git" "instale o git" git --version
requisito "Node 22 (nvm)" "instale com: nvm install 22" bash -c 'ls -d "$HOME"/.nvm/versions/node/v22.* >/dev/null 2>&1'
requisito "Google Chrome (só para os prints)" "instale o Google Chrome" \
  bash -c 'command -v google-chrome || command -v google-chrome-stable || command -v chromium || [ -d "/Applications/Google Chrome.app" ]'
requisito "Acesso ao Bitbucket por SSH" "cadastre a sua chave SSH no Bitbucket e peça acesso ao dono" \
  git ls-remote git@bitbucket.org:vinnialfonso/lunna-web.git HEAD
if [ "$PENDENCIAS" -gt 0 ]; then morrer "$PENDENCIAS requisito(s) pendente(s)." "resolva os itens ✘ acima e rode ./script/setup.sh de novo"; fi
if [ "$SO_VERIFICAR" -eq 1 ]; then ok "Requisitos atendidos."; exit 0; fi

passo "Front (lunna-web)"
if [ -e "$RAIZ_WEB/.git" ]; then ok "lunna-web já está em $RAIZ_WEB"
else
  git clone git@bitbucket.org:vinnialfonso/lunna-web.git "$RAIZ_WEB"
  ok "lunna-web baixado em $RAIZ_WEB"
fi

passo "Configuração do back (.env)"
if [ -f "$RAIZ_API/.env" ]; then ok ".env já existe"
else
  cp "$RAIZ_API/.env.example" "$RAIZ_API/.env"
  ok ".env criado a partir do .env.example (ML_CLIENT_ID/SECRET ficam vazios: não são necessários com os dados de demonstração)"
fi

passo "Dependências do front"
(cd "$RAIZ_WEB" && com_node22 npm ci --no-audit --no-fund >/dev/null)
ok "npm ci no lunna-web"

passo "Dependências dos prints"
if [ -f "$RAIZ_API/script/prints/package.json" ]; then
  (cd "$RAIZ_API/script/prints" && com_node22 npm ci --no-audit --no-fund >/dev/null)
  ok "npm ci em script/prints"
fi

echo; ok "Tudo pronto."; echo "   Próximo passo: ./script/dev-up.sh"
```

- [ ] **Step 6: Escrever `script/dev-up.sh` e `script/dev-down.sh`**

`script/dev-up.sh`:

```bash
#!/usr/bin/env bash
# Sobe o ambiente de teste local com dados de demonstração. Pode rodar de novo sem estragar nada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/dev-up.sh [--com-jobs]
Sobe o ambiente de teste: Postgres + API (http://localhost:3100) e o front (http://localhost:3101),
com os dados de demonstração (login demo@lunna.dev / lunna12345).
  --com-jobs   liga também o sincronizador (a conta demo não tem token do ML e registra falhas de sincronização)."
tratar_ajuda "$AJUDA" "$@"
COM_JOBS=0
if [ "${1:-}" = "--com-jobs" ]; then COM_JOBS=1; fi

[ -e "$RAIZ_WEB" ] || morrer "O front não está em $RAIZ_WEB." "rode ./script/setup.sh"
[ -f "$RAIZ_API/.env" ] || morrer "Falta o .env do back." "rode ./script/setup.sh"

passo "Conferindo as portas"
estado_api="$(estado_da_porta_api)"; estado_web="$(estado_da_porta_web)"
case "$estado_api" in
  outro:*) morrer "A porta 3100 está ocupada por outro projeto (${estado_api#outro:})." "encerre esse projeto e rode de novo; não force" ;;
esac
case "$estado_web" in
  outro:*) morrer "A porta 3101 está ocupada por outro projeto (${estado_web#outro:})." "encerre esse projeto e rode de novo; não force" ;;
esac
ok "portas 3100 e 3101 livres ou já deste projeto"

passo "Back (Postgres + API)"
servicos=(postgres api)
if [ "$COM_JOBS" -eq 1 ]; then servicos+=(jobs); fi
ERRO="$(mktemp)"; trap 'rm -f "$ERRO"' EXIT
if ! compose up -d "${servicos[@]}" >/dev/null 2>"$ERRO"; then
  cat "$ERRO" >&2
  if grep -qiE 'address pools|pool overlaps|network' "$ERRO"; then
    aviso "O Docker parece estar sem redes livres. NÃO apague redes de outros projetos."
  fi
  morrer "Não consegui subir o back." "chame o dono com a mensagem acima"
fi
esperar_url http://localhost:3100/up 180 || morrer "A API não respondeu em 3 minutos." "veja os logs: docker compose logs api"
ok "API no ar em http://localhost:3100"

passo "Dados de demonstração"
compose exec -T api bin/rails db:seed >/dev/null
ok "seed demo carregado (pode rodar de novo sem duplicar)"

passo "Front"
if [ "$estado_web" = "nosso" ]; then ok "front já estava no ar"
else
  subir_front_dev
  esperar_url http://localhost:3101/api/saude 180 || morrer "O front não respondeu em 3 minutos." "veja o log: evidencias/dev-web.log"
  ok "front no ar em http://localhost:3101"
fi

echo
ok "Tudo no ar."
echo "   Front:  http://localhost:3101"
echo "   API:    http://localhost:3100  (saúde: /up)"
echo "   Login:  demo@lunna.dev / lunna12345"
echo "   Para desligar: ./script/dev-down.sh"
```

`script/dev-down.sh`:

```bash
#!/usr/bin/env bash
# Desliga o ambiente de teste local. Os dados de teste ficam guardados.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/dev-down.sh
Desliga o front e o back do ambiente de teste. Só encerra a porta 3101 se o dono for o lunna-web deste projeto."
tratar_ajuda "$AJUDA" "$@"

passo "Front"
estado="$(estado_da_porta_web)"
case "$estado" in
  nosso) desligar_front_da_porta; ok "front desligado" ;;
  livre) ok "front já estava desligado" ;;
  outro:*) aviso "A porta 3101 é de outro projeto (${estado#outro:}). Não mexi nela." ;;
esac

passo "Back"
if compose down >/dev/null 2>&1; then ok "back desligado (os dados de teste ficam guardados)"
else aviso "Não consegui desligar o back. O Docker está aberto?"; fi
```

- [ ] **Step 7: Rodar os testes rápidos e o lento**

```bash
chmod +x script/*.sh script/testes/*.sh
bash script/testes/setup_test.sh          # esperado: todas ✔, exit 0
bash script/testes/dev_lento_test.sh      # esperado: todas ✔ (sobe Docker e o front; alguns minutos)
./script/testar-kit.sh
```
Expected: `✔ Kit em ordem.`

- [ ] **Step 8: Commit**

```bash
git add script
git commit -m "feat: ambiente local do kit — setup, dev-up e dev-down

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 3: `nova-branch.sh`

**Files:**
- Create: `script/nova-branch.sh`, `script/testes/nova_branch_test.sh`

**Interfaces:**
- Consumes: `RAIZ_API`, `RAIZ_WEB`, `slug_de`, `morrer`, `ok`, `tratar_ajuda`.
- Produces: branch `feature/<slug>` em `RAIZ_API` e `RAIZ_WEB` (ambos a partir da `main` atualizada). As Tarefas 4, 5 e 6 leem essa branch via `slug_da_branch`.

- [ ] **Step 1: Escrever o teste que falha**

`script/testes/nova_branch_test.sh` (usa repositórios temporários com `origin` local; `LUNNA_API_DIR` e `WEB_DIR` apontam para eles):

```bash
#!/usr/bin/env bash
# Testes de nova-branch.sh com repositórios git temporários.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
criar_repo() { # criar_repo nome — origin bare + clone com um commit na main
  git init -q --bare -b main "$T/$1-origin.git"
  git clone -q "$T/$1-origin.git" "$T/$1" 2>/dev/null
  echo x > "$T/$1/a.txt"; git -C "$T/$1" add a.txt; git -C "$T/$1" commit -q -m inicial
  git -C "$T/$1" push -q origin main
}
criar_repo api; criar_repo web
export LUNNA_API_DIR="$T/api" WEB_DIR="$T/web"
NB="$DIR/../nova-branch.sh"
atual() { git -C "$T/$1" branch --show-current; }

saida="$(bash "$NB" "Alerta de Preço" 2>&1)"; st=$?
esperar "cria a branch: exit 0" "0" "$st"
esperar "api na branch com slug sem acento" "feature/alerta-de-preco" "$(atual api)"
esperar "web na mesma branch" "feature/alerta-de-preco" "$(atual web)"

git -C "$T/api" switch -q main; git -C "$T/web" switch -q main

saida="$(bash "$NB" "alerta de preço" 2>&1)"; st=$?
esperar "branch que já existe: exit 1" "1" "$st"; contem "branch existente: mensagem" "$saida" "já existe"

echo sujo > "$T/web/novo.txt"
saida="$(bash "$NB" "outra coisa" 2>&1)"; st=$?
esperar "alteração pendente no web: exit 1" "1" "$st"; contem "alteração pendente: mensagem" "$saida" "alterações não salvas"
esperar "nada foi trocado no api quando o web recusou" "main" "$(atual api)"
rm "$T/web/novo.txt"

saida="$(bash "$NB" 2>&1)"; st=$?
esperar "sem nome: exit 1" "1" "$st"; contem "sem nome: mensagem" "$saida" "Faltou o nome"
saida="$(bash "$NB" '!!!' 2>&1)"; st=$?
esperar "nome só de símbolos: exit 1" "1" "$st"; contem "nome inválido: mensagem" "$saida" "nome de branch válido"

[ "$FALHAS" -eq 0 ]
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash script/testes/nova_branch_test.sh`
Expected: FAIL (`nova-branch.sh` não existe).

- [ ] **Step 3: Implementar `script/nova-branch.sh`**

```bash
#!/usr/bin/env bash
# Cria a branch feature/<nome> nos dois projetos a partir da main atualizada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/nova-branch.sh <nome da funcionalidade>
Cria a branch feature/<nome> no lunna-api e no lunna-web a partir da main atualizada.
Recusa se algum dos projetos tiver alterações não salvas ou se a branch já existir.
Exemplo: ./script/nova-branch.sh alerta preço acima da referência"
tratar_ajuda "$AJUDA" "$@"

[ $# -ge 1 ] || morrer "Faltou o nome da funcionalidade." "exemplo: ./script/nova-branch.sh alerta-preco-acima-referencia"
SLUG="$(slug_de "$*")"
[ -n "$SLUG" ] || morrer "O nome '$*' não gerou um nome de branch válido." "use letras e números"
BRANCH="feature/$SLUG"
REPOS=("$RAIZ_API" "$RAIZ_WEB")

# Valida os dois antes de mexer em qualquer um (nunca deixa um repo trocado e o outro não).
for repo in "${REPOS[@]}"; do
  nome="$(basename "$repo")"
  [ -e "$repo/.git" ] || morrer "$nome não é um repositório git em $repo." "rode ./script/setup.sh"
  [ -z "$(git -C "$repo" status --porcelain)" ] || morrer "$nome tem alterações não salvas." "termine ou descarte antes de começar outra funcionalidade (peça ajuda ao Claude)"
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    morrer "A branch $BRANCH já existe em $nome." "escolha outro nome ou continue nela: git switch $BRANCH"
  fi
done

for repo in "${REPOS[@]}"; do
  git -C "$repo" fetch -q origin
  git -C "$repo" switch -q main
  git -C "$repo" pull -q --ff-only origin main
  git -C "$repo" switch -q -c "$BRANCH"
  ok "$(basename "$repo"): branch $BRANCH criada a partir da main atualizada"
done
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `chmod +x script/nova-branch.sh script/testes/nova_branch_test.sh && bash script/testes/nova_branch_test.sh`
Expected: todas ✔, exit 0.

- [ ] **Step 5: Commit**

```bash
./script/testar-kit.sh && git add script && git commit -m "feat: nova-branch.sh cria feature/<nome> nos dois repos

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 4: `verificar.sh`

**Files:**
- Create: `script/verificar.sh`, `script/testes/verificar_test.sh`, `script/testes/verificar_lento_test.sh`

**Interfaces:**
- Consumes: `compose`, `com_node22`, `pasta_evidencias`, `slug_da_branch`, `RAIZ_API`, `RAIZ_WEB`.
- Produces (lidos pela Tarefa 6): `evidencias/<branch>/verificacao-<data-hora>.txt` (log completo) e `evidencias/<branch>/verificacao-resumo.txt` (texto simples: 1ª linha `Verificação de <branch> em <data> (commit <hash>)`, depois uma linha `✔`/`✘` por parte). Saída 0 só se tudo passar.

- [ ] **Step 1: Escrever os testes que falham**

`script/testes/verificar_test.sh` (rápido):

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

saida="$(bash "$DIR/../verificar.sh" --ajuda)"; st=$?
esperar "--ajuda: exit 0" "0" "$st"; contem "--ajuda descreve o alvo" "$saida" "[api|web|tudo]"
saida="$(bash "$DIR/../verificar.sh" xyz 2>&1)"; st=$?
esperar "alvo inválido: exit 1" "1" "$st"; contem "alvo inválido: mensagem" "$saida" "inválido"

[ "$FALHAS" -eq 0 ]
```

`script/testes/verificar_lento_test.sh` (Docker; roda com `--completo`):

```bash
#!/usr/bin/env bash
# Verde na árvore atual; VERMELHO (exit 1) quando um teste é quebrado de propósito.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

bash "$DIR/../verificar.sh" api >/dev/null 2>&1; esperar "árvore limpa: verificar api exit 0" "0" "$?"
if [ -d "$RAIZ_WEB/node_modules" ]; then
  bash "$DIR/../verificar.sh" web >/dev/null 2>&1; esperar "árvore limpa: verificar web exit 0" "0" "$?"
fi

ESPEC="$RAIZ_API/spec/tmp_kit_falha_spec.rb"
trap 'rm -f "$ESPEC"' EXIT
printf 'RSpec.describe("kit") { it("falha de proposito") { expect(1).to eq(2) } }\n' > "$ESPEC"
saida="$(bash "$DIR/../verificar.sh" api 2>&1)"; st=$?
esperar "teste quebrado de propósito: exit 1" "1" "$st"
contem "mostra ✘ nos testes da API" "$saida" "✘ API  testes"
contem "resumo em arquivo marca ✘" "$(cat "$(pasta_evidencias)/verificacao-resumo.txt")" "✘ API  testes"
rm -f "$ESPEC"

[ "$FALHAS" -eq 0 ]
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash script/testes/verificar_test.sh`
Expected: FAIL (`verificar.sh` não existe).

- [ ] **Step 3: Implementar `script/verificar.sh`**

```bash
#!/usr/bin/env bash
# Roda a verificação completa antes de um PR. Log em evidencias/<branch>/verificacao-<data>.txt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/verificar.sh [api|web|tudo]   (padrão: tudo)
Roda o que o dono usa para aprovar um PR:
  back   testes (RSpec), estilo (RuboCop), segurança (Brakeman) e bibliotecas (bundler-audit)
  front  tipos (typecheck), estilo (ESLint) e testes (Vitest)
Log completo: evidencias/<branch>/verificacao-<data>.txt · resumo: evidencias/<branch>/verificacao-resumo.txt"
tratar_ajuda "$AJUDA" "$@"

ALVO="${1:-tudo}"
case "$ALVO" in api|web|tudo) ;; *) morrer "Alvo '$ALVO' inválido." "use api, web ou tudo" ;; esac

PASTA="$(pasta_evidencias)"
LOG="$PASTA/verificacao-$(date +%Y-%m-%d-%H%M).txt"
RESUMO="$PASTA/verificacao-resumo.txt"
: > "$LOG"
printf 'Verificação de %s em %s (commit %s)\n' "$(slug_da_branch)" "$(date '+%Y-%m-%d %H:%M')" \
  "$(git -C "$RAIZ_API" rev-parse --short HEAD 2>/dev/null || echo '?')" > "$RESUMO"
FALHOU=0

# rodar "Rótulo" "regex do resumo" função [args…] — executa, guarda a saída no log e registra ✔/✘.
# O status vem direto do comando (sem pipe), então nada engole uma falha.
rodar() {
  local rotulo="$1" padrao="$2" inicio status extra=""; shift 2
  inicio="$(wc -c < "$LOG")"
  printf '\n===== %s =====\n' "$rotulo" >> "$LOG"
  set +e; "$@" >> "$LOG" 2>&1; status=$?; set -e
  if [ -n "$padrao" ]; then
    extra="$(tail -c +"$((inicio + 1))" "$LOG" | grep -E "$padrao" | tail -1 | sed -E 's/\x1b\[[0-9;]*m//g' || true)"
  fi
  if [ "$status" -eq 0 ]; then ok "$rotulo $extra"; printf '✔ %s %s\n' "$rotulo" "$extra" >> "$RESUMO"
  else falha "$rotulo $extra"; printf '✘ %s %s\n' "$rotulo" "$extra" >> "$RESUMO"; FALHOU=1; fi
}

api_testes()     { (cd "$RAIZ_API" && compose run --rm -T -e RAILS_ENV=test api bash -c "bin/rails db:prepare >/dev/null && bundle exec rspec --format documentation"); }
api_estilo()     { (cd "$RAIZ_API" && compose run --rm -T api bundle exec rubocop); }
api_seguranca()  { (cd "$RAIZ_API" && compose run --rm -T api bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error); }
api_bibliotecas(){ (cd "$RAIZ_API" && compose run --rm -T api bin/bundler-audit); }
web_tipos()      { (cd "$RAIZ_WEB" && com_node22 npm run -s typecheck); }
web_estilo()     { (cd "$RAIZ_WEB" && com_node22 npm run -s lint); }
web_testes()     { (cd "$RAIZ_WEB" && com_node22 npm run -s test); }

passo "Verificando ($ALVO) — log em evidencias/$(slug_da_branch)/"
if [ "$ALVO" = api ] || [ "$ALVO" = tudo ]; then
  rodar "API  testes     " '[0-9]+ examples,' api_testes
  rodar "API  estilo     " '' api_estilo
  rodar "API  segurança  " '' api_seguranca
  rodar "API  bibliotecas" '' api_bibliotecas
fi
if [ "$ALVO" = web ] || [ "$ALVO" = tudo ]; then
  [ -e "$RAIZ_WEB" ] || morrer "O front não está em $RAIZ_WEB." "rode ./script/setup.sh"
  rodar "WEB  tipos      " '' web_tipos
  rodar "WEB  estilo     " '' web_estilo
  rodar "WEB  testes     " 'Tests +[0-9]+' web_testes
fi

echo
printf 'Log completo: %s\n' "$LOG"
if [ "$FALHOU" -eq 0 ]; then ok "Tudo verde. Pode seguir para os prints e o PR."
else
  if grep -q '^Failures:' "$LOG"; then echo; echo "Primeiras falhas dos testes do back:"; sed -n '/^Failures:/,/^Finished in/p' "$LOG" | head -30; fi
  morrer "A verificação falhou." "peça ao Claude: /lunna-verificar (ele lê o log e corrige)"
fi
```

- [ ] **Step 4: Rodar os testes**

```bash
chmod +x script/verificar.sh script/testes/verificar_test.sh script/testes/verificar_lento_test.sh
bash script/testes/verificar_test.sh           # esperado: ✔, exit 0
bash script/testes/verificar_lento_test.sh     # esperado: ✔ (alguns minutos: RSpec, RuboCop, Brakeman, bundler-audit, web)
```
Se o `bundler-audit` falhar por falta de rede, o teste "árvore limpa" falha: é comportamento correto (a mensagem indica a causa no log); rode com rede.

- [ ] **Step 5: Commit**

```bash
./script/testar-kit.sh && git add script && git commit -m "feat: verificar.sh roda testes, estilo e segurança dos dois repos

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 5: Prints — `prints.sh`, `tirar-prints.mjs` e o roteiro base

**Files:**
- Create: `script/prints.sh`, `script/prints/package.json`, `script/prints/package-lock.json` (gerado), `script/prints/tirar-prints.mjs`, `script/prints/roteiros/base.json`, `script/testes/prints_test.sh`, `script/testes/prints_lento_test.sh`

**Interfaces:**
- Consumes: `estado_da_porta_api`, `estado_da_porta_web`, `desligar_front_da_porta`, `subir_front_dev`, `esperar_url`, `pasta_evidencias`, `com_node22`, `RAIZ_KIT`, `RAIZ_WEB`; o ambiente no ar (`dev-up.sh`); cookie de sessão `lunna_token`, chave de tema `lunna:tema` (`claro`/`escuro`) e `POST /auth/sign_in` → `{token}` da API.
- Produces (lidos pela Tarefa 6): `evidencias/<branch>/prints/NN-<cena>-<claro|escuro|mobile>.png`, numerados em sequência (cena 1 → 01, 02, 03; cena 2 → 04, 05, 06…). Formato do roteiro: `{ "cenas": [ { "nome", "rota", "esperar", "login"?: false, "paginaInteira"?: true, "acoes"?: [ {"clicar": sel} | {"esperar": sel} | {"digitar": {"seletor","texto"}} | {"rolar": px} ] } ] }`; `esperar` é um seletor do Playwright que **precisa** aparecer, senão a cena falha.

- [ ] **Step 1: Escrever os testes que falham**

`script/testes/prints_test.sh` (rápido):

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

saida="$(bash "$DIR/../prints.sh" --ajuda)"; st=$?
esperar "--ajuda: exit 0" "0" "$st"; contem "--ajuda cita a porta 3101" "$saida" "3101"
saida="$(bash "$DIR/../prints.sh" /caminho/que/nao/existe.json 2>&1)"; st=$?
esperar "roteiro inexistente: exit 1" "1" "$st"; contem "roteiro inexistente: mensagem" "$saida" "Roteiro não encontrado"
python3 -c "import json,sys; d=json.load(open('$DIR/../prints/roteiros/base.json')); assert len(d['cenas'])>=5 and all('esperar' in c and 'rota' in c for c in d['cenas'])" \
  && ok "roteiro base tem 5+ cenas com rota e esperar" || { falha "roteiro base inválido"; FALHAS=$((FALHAS+1)); }

[ "$FALHAS" -eq 0 ]
```

`script/testes/prints_lento_test.sh` (Docker + Chrome; `--completo`):

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

for p in 3100 3101; do
  if porta_em_uso "$p"; then aviso "porta $p ocupada; teste lento de prints pulado (rode dev-down.sh antes)"; exit 0; fi
done
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; bash "$DIR/../dev-down.sh" >/dev/null 2>&1' EXIT
bash "$DIR/../dev-up.sh" >/dev/null 2>&1 || { falha "dev-up falhou"; exit 1; }
PASTA="$(pasta_evidencias)"

# 1) Uma cena pública: 3 arquivos (claro, escuro, mobile), todos com conteúdo, e o dev-server volta ao final.
printf '{"cenas":[{"nome":"login","rota":"/login","login":false,"esperar":"text=Entrar na sua conta"}]}\n' > "$TMP/uma.json"
saida="$(bash "$DIR/../prints.sh" "$TMP/uma.json" 2>&1)"; st=$?
esperar "prints de uma cena: exit 0" "0" "$st"
for arq in 01-login-claro.png 02-login-escuro.png 03-login-mobile.png; do
  tam="$(wc -c < "$PASTA/prints/$arq" 2>/dev/null || echo 0)"
  if [ "$tam" -gt 15000 ]; then ok "$arq gerado ($tam bytes)"; else falha "$arq ausente ou vazio ($tam bytes)"; FALHAS=$((FALHAS+1)); fi
done
esperar "front de desenvolvimento voltou depois dos prints" "nosso" "$(estado_da_porta_web)"

# 2) Seletor que nunca aparece: falha com o nome da cena e não salva print em branco.
printf '{"cenas":[{"nome":"nada","rota":"/login","login":false,"esperar":"text=Isto nunca aparece na tela"}]}\n' > "$TMP/nada.json"
saida="$(bash "$DIR/../prints.sh" "$TMP/nada.json" 2>&1)"; st=$?
esperar "seletor ausente: exit 1" "1" "$st"; contem "seletor ausente: cita a cena" "$saida" "✘ nada"
esperar "seletor ausente: nenhum png salvo" "0" "$(find "$PASTA/prints" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"

# 3) Porta 3101 de outro projeto: recusa e não mexe nela.
desligar_front_da_porta
( cd "$TMP" && exec python3 -m http.server 3101 --bind 127.0.0.1 >/dev/null 2>&1 ) &
SERVIDOR=$!; sleep 1
saida="$(bash "$DIR/../prints.sh" "$TMP/uma.json" 2>&1)"; st=$?
esperar "porta 3101 alheia: exit 1" "1" "$st"; contem "porta 3101 alheia: cita 'outro projeto'" "$saida" "outro projeto"
if kill -0 "$SERVIDOR" 2>/dev/null; then ok "o servidor alheio continuou de pé"; else falha "o script matou o servidor alheio"; FALHAS=$((FALHAS+1)); fi
kill "$SERVIDOR" 2>/dev/null; wait "$SERVIDOR" 2>/dev/null

[ "$FALHAS" -eq 0 ]
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash script/testes/prints_test.sh`
Expected: FAIL (`prints.sh` não existe).

- [ ] **Step 3: Criar `script/prints/package.json` e instalar (lockfile com URLs públicas)**

```json
{
  "name": "lunna-prints",
  "private": true,
  "type": "module",
  "description": "Prints das telas do Lunna para os PRs (usado por script/prints.sh).",
  "dependencies": { "playwright-core": "^1.50.0" }
}
```

```bash
(cd script/prints && PATH="$(ls -d ~/.nvm/versions/node/v22.* | sort -V | tail -1)/bin:$PATH" npm install --registry=https://registry.npmjs.org/ --no-audit --no-fund)
grep -c "pkgs.dev.azure.com" script/prints/package-lock.json || true
```
Expected: `package-lock.json` criado e a contagem de `pkgs.dev.azure.com` = `0` (o lockfile não pode apontar para o feed privado da Locaweb: a pessoa não tem acesso).

- [ ] **Step 4: Criar `script/prints/roteiros/base.json`**

```json
{
  "cenas": [
    { "nome": "login", "rota": "/login", "login": false, "esperar": "text=Entrar na sua conta" },
    { "nome": "visao-geral", "rota": "/", "esperar": "text=Precisa de atenção" },
    { "nome": "anuncios", "rota": "/anuncios", "esperar": "input[placeholder*='Buscar por título']" },
    { "nome": "curva-abc", "rota": "/curva-abc", "esperar": "text=Curva A" },
    { "nome": "configuracoes", "rota": "/configuracoes", "esperar": "text=Gerencie sua empresa" }
  ]
}
```

- [ ] **Step 5: Escrever `script/prints/tirar-prints.mjs`**

```js
#!/usr/bin/env node
// Tira os prints de um roteiro: node tirar-prints.mjs <roteiro.json> <pasta-de-saída>
// Cada cena vira 3 arquivos: NN-<cena>-claro.png, NN-<cena>-escuro.png (desktop 1440x900)
// e NN-<cena>-mobile.png (360x800, tema claro), numerados em sequência.
// Env: FRONT_URL (padrão http://localhost:3101), API_URL (http://localhost:3100),
//      LOGIN_EMAIL / LOGIN_SENHA (padrão: o login demo do seed), CHROME_PATH (opcional).
import { chromium } from 'playwright-core'
import { readFile, mkdir } from 'node:fs/promises'
import path from 'node:path'

const FRONT = process.env.FRONT_URL ?? 'http://localhost:3101'
const API = process.env.API_URL ?? 'http://localhost:3100'
const EMAIL = process.env.LOGIN_EMAIL ?? 'demo@lunna.dev'
const SENHA = process.env.LOGIN_SENHA ?? 'lunna12345'
const ESPERA_MS = 15000

const VARIANTES = [
  { sufixo: 'claro', tema: 'claro', viewport: { width: 1440, height: 900 } },
  { sufixo: 'escuro', tema: 'escuro', viewport: { width: 1440, height: 900 } },
  { sufixo: 'mobile', tema: 'claro', viewport: { width: 360, height: 800 } }
]

async function entrar() {
  const resposta = await fetch(`${API}/auth/sign_in`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: EMAIL, password: SENHA })
  })
  if (!resposta.ok) {
    throw new Error(`Login demo falhou (HTTP ${resposta.status}). O seed foi carregado? Rode ./script/dev-up.sh`)
  }
  return (await resposta.json()).token
}

async function executarAcao(page, acao) {
  if (acao.clicar) await page.click(acao.clicar, { timeout: ESPERA_MS })
  if (acao.digitar) await page.fill(acao.digitar.seletor, acao.digitar.texto, { timeout: ESPERA_MS })
  if (acao.rolar) await page.mouse.wheel(0, acao.rolar)
  if (acao.esperar) await page.waitForSelector(acao.esperar, { timeout: ESPERA_MS })
}

const [roteiroPath, saida] = process.argv.slice(2)
if (!roteiroPath || !saida) {
  console.error('Uso: node tirar-prints.mjs <roteiro.json> <pasta-de-saída>')
  process.exit(2)
}
const roteiro = JSON.parse(await readFile(roteiroPath, 'utf8'))
await mkdir(saida, { recursive: true })
const token = await entrar()

const browser = await chromium.launch(
  process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : { channel: 'chrome' }
)
let numero = 0
for (const cena of roteiro.cenas) {
  for (const variante of VARIANTES) {
    numero += 1
    const arquivo = `${String(numero).padStart(2, '0')}-${cena.nome}-${variante.sufixo}.png`
    const contexto = await browser.newContext({
      viewport: variante.viewport, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo'
    })
    try {
      if (cena.login !== false) await contexto.addCookies([{ name: 'lunna_token', value: token, url: FRONT }])
      await contexto.addInitScript(([chave, valor]) => localStorage.setItem(chave, valor), ['lunna:tema', variante.tema])
      const page = await contexto.newPage()
      await page.goto(`${FRONT}${cena.rota}`, { waitUntil: 'networkidle' })
      // Sem o elemento esperado a cena FALHA: nunca salvamos um print de tela em branco ou errada.
      await page.waitForSelector(cena.esperar, { timeout: ESPERA_MS })
      for (const acao of cena.acoes ?? []) await executarAcao(page, acao)
      await page.screenshot({ path: path.join(saida, arquivo), fullPage: cena.paginaInteira === true })
      console.log(`✔ ${arquivo}`)
    } catch (erro) {
      console.error(`✘ ${cena.nome} (${variante.sufixo}): ${String(erro.message).split('\n')[0]}`)
      process.exitCode = 1
    } finally {
      await contexto.close()
    }
  }
}
await browser.close()
```

- [ ] **Step 6: Escrever `script/prints.sh`**

```bash
#!/usr/bin/env bash
# Tira os prints numerados das telas do roteiro, com o build de PRODUÇÃO do front na porta 3101.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/prints.sh [roteiro.json]
Tira os prints numerados (claro, escuro e celular) das telas do roteiro, com o login demo, e salva em
evidencias/<branch>/prints/. Usa o build de PRODUÇÃO do front na porta 3101.
Sem argumento usa evidencias/<branch>/roteiro.json (se existir) ou script/prints/roteiros/base.json.
O ambiente precisa estar no ar (./script/dev-up.sh)."
tratar_ajuda "$AJUDA" "$@"

PASTA="$(pasta_evidencias)"
ROTEIRO="${1:-}"
if [ -z "$ROTEIRO" ]; then
  if [ -f "$PASTA/roteiro.json" ]; then ROTEIRO="$PASTA/roteiro.json"; else ROTEIRO="$RAIZ_KIT/script/prints/roteiros/base.json"; fi
fi
[ -f "$ROTEIRO" ] || morrer "Roteiro não encontrado: $ROTEIRO." "confira o caminho ou use o roteiro padrão (sem argumento)"
[ -e "$RAIZ_WEB" ] || morrer "O front não está em $RAIZ_WEB." "rode ./script/setup.sh"
[ -d "$RAIZ_KIT/script/prints/node_modules/playwright-core" ] || morrer "As dependências dos prints não estão instaladas." "rode ./script/setup.sh"
bash -c 'command -v google-chrome || command -v google-chrome-stable || command -v chromium || [ -d "/Applications/Google Chrome.app" ]' >/dev/null 2>&1 \
  || morrer "Google Chrome não encontrado." "instale o Google Chrome (é usado só para tirar os prints)"

passo "Conferindo o back (API)"
estado_api="$(estado_da_porta_api)"
case "$estado_api" in
  nosso) ok "API deste projeto no ar (porta 3100)" ;;
  outro:*) morrer "A porta 3100 é de outro projeto (${estado_api#outro:})." "encerre esse projeto e rode ./script/dev-up.sh" ;;
  *) morrer "A API não está no ar." "rode ./script/dev-up.sh" ;;
esac

estado_web="$(estado_da_porta_web)"
case "$estado_web" in
  outro:*) morrer "A porta 3101 é de outro projeto (${estado_web#outro:})." "encerre esse projeto e rode de novo; não force" ;;
esac
RESTAURAR_DEV=0
if [ "$estado_web" = nosso ]; then RESTAURAR_DEV=1; desligar_front_da_porta; fi
limpar() {
  desligar_front_da_porta
  if [ "$RESTAURAR_DEV" -eq 1 ]; then subir_front_dev; fi
}
trap limpar EXIT

passo "Build de produção do front"
(cd "$RAIZ_WEB" && com_node22 npm run build >"$PASTA/build-web.log" 2>&1) || morrer "O build do front falhou." "veja o log: $PASTA/build-web.log"
ok "build pronto"

passo "Servindo o build na porta 3101"
( cd "$RAIZ_WEB" && HOST=127.0.0.1 PORT=3101 NUXT_PUBLIC_API_URL=http://localhost:3100 \
    com_node22 nohup node .output/server/index.mjs >"$PASTA/front-prod.log" 2>&1 & )
esperar_url http://localhost:3101/api/saude 60 || morrer "O front de produção não subiu." "veja o log: $PASTA/front-prod.log"
# Dono real da porta: precisa ser o lunna-web deste projeto, senão o print sairia de outra versão.
[ "$(estado_da_porta_web)" = nosso ] || morrer "A porta 3101 não é do lunna-web deste projeto." "veja quem usa: ss -ltnp | grep 3101"
ok "front de produção no ar (dono da porta conferido)"

passo "Tirando os prints"
SAIDA="$PASTA/prints"; rm -rf "$SAIDA"; mkdir -p "$SAIDA"
set +e
(cd "$RAIZ_KIT/script/prints" && com_node22 node tirar-prints.mjs "$ROTEIRO" "$SAIDA")
status=$?
set -e
[ "$status" -eq 0 ] || morrer "Alguma cena falhou (veja os ✘ acima)." "confira a tela em http://localhost:3101 e o seletor \"esperar\" do roteiro"
total="$(find "$SAIDA" -name '*.png' | wc -l | tr -d ' ')"
[ "$total" -gt 0 ] || morrer "Nenhum print foi gerado." "confira o roteiro"
ok "$total prints em ${SAIDA#"$RAIZ_API"/}"
echo "   Abra as imagens e confira: o que você pediu aparece? o texto está certo? nenhum dado real ou secreto?"
```

- [ ] **Step 7: Rodar os testes**

```bash
chmod +x script/prints.sh script/testes/prints_test.sh script/testes/prints_lento_test.sh
bash script/testes/prints_test.sh          # esperado: ✔, exit 0
bash script/testes/prints_lento_test.sh    # esperado: ✔ (sobe o ambiente, faz build de produção 3 vezes, Chrome)
```
Expected: todas ✔. Conferir a olho um dos PNGs de `evidencias/<branch>/prints/` (ler a imagem): a tela de login em tema claro, sem erro.

- [ ] **Step 8: Commit**

```bash
./script/testar-kit.sh && git add script && git commit -m "feat: prints.sh tira prints numerados (claro, escuro e celular) do build de produção

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 6: `pr.sh` e o modelo do PR

**Files:**
- Create: `script/pr.sh`, `docs/modelos/pr.md`, `script/testes/pr_test.sh`
- Modify: `script/lib/comum.sh` (função `link_pr`), `script/testes/comum_test.sh` (teste da `link_pr`)

**Interfaces:**
- Consumes: `pasta_evidencias`, `slug_da_branch`, `RAIZ_KIT`, `RAIZ_API`, `RAIZ_WEB`; de `verificar.sh` o arquivo `evidencias/<branch>/verificacao-resumo.txt`; de `prints.sh` os PNGs `NN-<cena>-<claro|escuro|mobile>.png`; do executor (skill `lunna-pr`) os arquivos `resumo.md`, `como-testar.md` e (opcional) `titulo.txt` na mesma pasta.
- Produces: `evidencias/<branch>/PR.md` (sem `{{`), e no terminal o comando de envio e o link de PR de cada repo alterado. `link_pr URL BRANCH` → link do Bitbucket ou vazio.

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar ao fim de `script/testes/comum_test.sh`, antes da linha `[ "$FALHAS" -eq 0 ]`:

```bash
# --- link_pr ---
esperar "link_pr de URL SSH do Bitbucket" \
  "https://bitbucket.org/vinnialfonso/lunna-web/pull-requests/new?source=feature/x&dest=main" \
  "$(link_pr 'git@bitbucket.org:vinnialfonso/lunna-web.git' 'feature/x')"
esperar "link_pr de URL HTTPS do Bitbucket" \
  "https://bitbucket.org/vinnialfonso/lunna-api/pull-requests/new?source=feature/x&dest=main" \
  "$(link_pr 'https://bitbucket.org/vinnialfonso/lunna-api.git' 'feature/x')"
esperar "link_pr de origin que não é do Bitbucket fica vazio" "" "$(link_pr '/tmp/origin.git' 'feature/x')"
```

`script/testes/pr_test.sh`:

```bash
#!/usr/bin/env bash
# Testes de pr.sh com repositórios git temporários (origin local).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/comum.sh"
FALHAS=0
esperar() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$2', obtido '$3')"; FALHAS=$((FALHAS+1)); fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — faltou '$3' em: $2"; FALHAS=$((FALHAS+1)) ;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
criar_repo() {
  git init -q --bare -b main "$T/$1-origin.git"
  git clone -q "$T/$1-origin.git" "$T/$1" 2>/dev/null
  echo x > "$T/$1/a.txt"; git -C "$T/$1" add a.txt; git -C "$T/$1" commit -q -m inicial
  git -C "$T/$1" push -q origin main
}
criar_repo api; criar_repo web
export LUNNA_API_DIR="$T/api" WEB_DIR="$T/web"
PR="$DIR/../pr.sh"
EV="$T/api/evidencias/feature-teste"

# 1) Na main: recusa.
saida="$(bash "$PR" 2>&1)"; st=$?
esperar "na main: exit 1" "1" "$st"; contem "na main: mensagem" "$saida" "main"

# 2) Branch sem commits novos: recusa (depois do resumo, para isolar o motivo).
git -C "$T/api" switch -q -c feature/teste; git -C "$T/web" switch -q -c feature/teste
mkdir -p "$EV"
saida="$(bash "$PR" 2>&1)"; st=$?
esperar "sem resumo: exit 1" "1" "$st"; contem "sem resumo: mensagem" "$saida" "resumo.md"
printf 'Novo alerta que mostra anúncios com preço acima da referência.\n' > "$EV/resumo.md"
printf '1. Entre com demo@lunna.dev / lunna12345.\n2. Abra a Visão geral.\n' > "$EV/como-testar.md"
saida="$(bash "$PR" 2>&1)"; st=$?
esperar "sem verificação: exit 1" "1" "$st"; contem "sem verificação: mensagem" "$saida" "verificar.sh"
printf 'Verificação de feature-teste em 2026-09-25 10:00 (commit abc123)\n✘ API  testes      1 examples, 1 failure\n' > "$EV/verificacao-resumo.txt"
saida="$(bash "$PR" 2>&1)"; st=$?
esperar "verificação com ✘: exit 1" "1" "$st"; contem "verificação com ✘: mensagem" "$saida" "falhas"
printf 'Verificação de feature-teste em 2026-09-25 10:00 (commit abc123)\n✔ API  testes      413 examples, 0 failures\n✔ WEB  testes      Tests  236 passed (236)\n' > "$EV/verificacao-resumo.txt"
saida="$(bash "$PR" 2>&1)"; st=$?
esperar "sem commits novos: exit 1" "1" "$st"; contem "sem commits novos: mensagem" "$saida" "commits"

# 3) Mudança visual no front sem prints: recusa.
mkdir -p "$T/web/app/components"; echo '<template/>' > "$T/web/app/components/Alerta.vue"
git -C "$T/web" add -A; git -C "$T/web" commit -q -m "feat: alerta"
saida="$(bash "$PR" 2>&1)"; st=$?
esperar "mudança visual sem prints: exit 1" "1" "$st"; contem "mudança visual sem prints: mensagem" "$saida" "prints.sh"

# 4) Caminho feliz: com prints, gera PR.md sem placeholders.
mkdir -p "$EV/prints"
for f in 01-visao-geral-claro 02-visao-geral-escuro 03-visao-geral-mobile; do : > "$EV/prints/$f.png"; done
printf 'Alerta: preço acima da referência\n' > "$EV/titulo.txt"
saida="$(bash "$PR" 2>&1)"; st=$?
esperar "caminho feliz: exit 0" "0" "$st"
[ -s "$EV/PR.md" ] && ok "PR.md criado" || { falha "PR.md não foi criado"; FALHAS=$((FALHAS+1)); }
pr="$(cat "$EV/PR.md" 2>/dev/null || true)"
case "$pr" in *"{{"*) falha "PR.md sobrou placeholder {{"; FALHAS=$((FALHAS+1)) ;; *) ok "PR.md sem placeholders" ;; esac
contem "PR.md tem o título" "$pr" "# Alerta: preço acima da referência"
contem "PR.md tem o resumo" "$pr" "anúncios com preço acima da referência"
contem "PR.md legenda do print (claro)" "$pr" "visao-geral, tema claro"
contem "PR.md legenda do print (celular)" "$pr" "visao-geral, celular (360 px)"
contem "PR.md lista o arquivo mudado do front" "$pr" "app/components/Alerta.vue"
contem "PR.md traz o resultado da verificação" "$pr" "413 examples, 0 failures"
contem "PR.md traz o checklist" "$pr" "somente leitura no Mercado Livre"
contem "saída mostra o comando de envio" "$saida" "git -C"

[ "$FALHAS" -eq 0 ]
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash script/testes/comum_test.sh; bash script/testes/pr_test.sh`
Expected: FAIL (`link_pr: command not found`; `pr.sh` não existe).

- [ ] **Step 3: Acrescentar `link_pr` ao fim de `script/lib/comum.sh`**

```bash

# link_pr URL_DO_ORIGIN BRANCH — link para abrir o PR no Bitbucket (vazio se o origin não for do Bitbucket).
link_pr() {
  local url="$1" branch="$2" repo
  repo="$(printf '%s' "$url" | sed -nE 's#^.*bitbucket\.org[:/]([^/]+/[^/]+)$#\1#p' | sed -E 's#\.git$##')"
  if [ -n "$repo" ]; then printf 'https://bitbucket.org/%s/pull-requests/new?source=%s&dest=main' "$repo" "$branch"; fi
}
```

- [ ] **Step 4: Criar o modelo `docs/modelos/pr.md`**

````markdown
# {{TITULO}}

## Resumo (o que muda para o vendedor)

{{RESUMO}}

## Como testar

{{COMO_TESTAR}}

## O que mudou

Branch: `{{BRANCH}}`

{{ARQUIVOS}}
## Evidências (prints)

{{PRINTS}}

## Verificação

```
{{VERIFICACAO}}
```

## Checklist das regras de ouro

- [ ] O Lunna continua somente leitura no Mercado Livre (nenhuma chamada de escrita).
- [ ] Tudo escopado por empresa (nada de `company_id` vindo de parâmetro; anúncio de outra empresa dá 404).
- [ ] Cálculo e regra de negócio no back; o front só exibe.
- [ ] Parâmetros de negócio vêm da empresa, nada fixo no código.
- [ ] Nenhum segredo em código, log, print ou neste PR.
- [ ] Nenhum campo novo da API do ML sem exemplo real salvo como fixture.
- [ ] Testes escritos junto com o código; verificação verde.
- [ ] Não mexi em `cd/prod/`, `.env*`, `docs/DECISOES.md`, dependências ou deploy (ou o dono aprovou).
````

- [ ] **Step 5: Implementar `script/pr.sh`**

```bash
#!/usr/bin/env bash
# Monta evidencias/<branch>/PR.md e imprime o link de PR de cada projeto alterado.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/comum.sh"

AJUDA="Uso: script/pr.sh
Monta evidencias/<branch>/PR.md e imprime o link para abrir o PR de cada projeto alterado.
Antes, escreva (ou peça ao Claude: /lunna-pr) em evidencias/<branch>/:
  resumo.md       o que muda para o vendedor, em linguagem de negócio
  como-testar.md  passos com o login demo
  titulo.txt      título do PR (opcional; sem ele usa o nome da branch)
E rode ./script/verificar.sh tudo (e ./script/prints.sh se a mudança mexe em telas)."
tratar_ajuda "$AJUDA" "$@"

BRANCH="$(git -C "$RAIZ_API" branch --show-current)"
if [ -z "$BRANCH" ] || [ "$BRANCH" = main ]; then
  morrer "Você está na main (ou sem branch)." "crie uma branch com ./script/nova-branch.sh <nome>"
fi
PASTA="$(pasta_evidencias)"
REL="evidencias/$(slug_da_branch)"

for arquivo in resumo.md como-testar.md; do
  [ -s "$PASTA/$arquivo" ] || morrer "Falta $REL/$arquivo." "escreva o arquivo (ou peça ao Claude: /lunna-pr)"
done
[ -s "$PASTA/verificacao-resumo.txt" ] || morrer "Não há verificação para esta branch." "rode ./script/verificar.sh tudo"
if grep -q '^✘' "$PASTA/verificacao-resumo.txt"; then
  morrer "A última verificação tem falhas (✘)." "corrija e rode ./script/verificar.sh tudo de novo"
fi

# Projetos com commits novos nesta branch (alterações sem commit NÃO entram no PR).
ALTERADOS=()
for repo in "$RAIZ_API" "$RAIZ_WEB"; do
  [ -e "$repo/.git" ] || continue
  if [ "$(git -C "$repo" branch --show-current)" = "$BRANCH" ] && [ "$(git -C "$repo" rev-list --count origin/main..HEAD)" -gt 0 ]; then
    ALTERADOS+=("$repo")
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then aviso "$(basename "$repo") tem alterações sem commit: elas NÃO entram no PR."; fi
  fi
done
[ "${#ALTERADOS[@]}" -gt 0 ] || morrer "Nenhum projeto tem commits novos na branch $BRANCH." "salve o trabalho com commit (o Claude faz isso) e rode de novo"

# Mudança de tela exige prints.
TEM_PRINTS=0
if [ -n "$(find "$PASTA/prints" -name '*.png' 2>/dev/null | head -1)" ]; then TEM_PRINTS=1; fi
for repo in "${ALTERADOS[@]}"; do
  if git -C "$repo" diff --name-only origin/main...HEAD | grep -qE '^app/(pages|components|assets)/' && [ "$TEM_PRINTS" -eq 0 ]; then
    morrer "Esta mudança altera telas e não há prints." "rode ./script/prints.sh e confira as imagens"
  fi
done

# Peças do texto do PR.
if [ -s "$PASTA/titulo.txt" ]; then PR_TITULO="$(head -1 "$PASTA/titulo.txt")"; else PR_TITULO="$(printf '%s' "${BRANCH#feature/}" | tr '-' ' ')"; fi
PR_BRANCH="$BRANCH"
PR_RESUMO="$(cat "$PASTA/resumo.md")"
PR_COMO_TESTAR="$(cat "$PASTA/como-testar.md")"
PR_VERIFICACAO="$(cat "$PASTA/verificacao-resumo.txt")"
PR_ARQUIVOS=""
for repo in "${ALTERADOS[@]}"; do
  PR_ARQUIVOS+="**$(basename "$repo")**"$'\n\n```\n'"$(git -C "$repo" diff --stat origin/main...HEAD)"$'\n```\n\n'
done
PR_PRINTS=""; n=0
for arquivo in "$PASTA"/prints/*.png; do
  [ -e "$arquivo" ] || continue
  n=$((n + 1)); base="$(basename "$arquivo" .png)"; variante="${base##*-}"; cena="${base#*-}"; cena="${cena%-*}"
  case "$variante" in claro) legenda="tema claro" ;; escuro) legenda="tema escuro" ;; mobile) legenda="celular (360 px)" ;; *) legenda="$variante" ;; esac
  PR_PRINTS+="$n. \`$(basename "$arquivo")\` — $cena, $legenda"$'\n'
done
if [ -z "$PR_PRINTS" ]; then PR_PRINTS="Mudança sem tela: sem prints."; fi

export PR_TITULO PR_BRANCH PR_RESUMO PR_COMO_TESTAR PR_VERIFICACAO PR_ARQUIVOS PR_PRINTS
perl -0pe 's{\{\{(\w+)\}\}}{ defined $ENV{"PR_$1"} ? $ENV{"PR_$1"} : die "variável PR_$1 ausente no modelo\n" }ge' \
  "$RAIZ_KIT/docs/modelos/pr.md" > "$PASTA/PR.md"
if grep -q '{{' "$PASTA/PR.md"; then morrer "O PR.md ficou com placeholder ({{...})." "confira o modelo docs/modelos/pr.md"; fi
ok "PR.md criado em $REL/PR.md"

echo
echo "Próximos passos (um PR por projeto alterado):"
for repo in "${ALTERADOS[@]}"; do
  link="$(link_pr "$(git -C "$repo" remote get-url origin)" "$BRANCH")"
  echo "  • $(basename "$repo")"
  echo "      1) enviar a branch:  git -C \"$repo\" push -u origin $BRANCH"
  echo "      2) abrir o PR:       ${link:-abra o PR no Bitbucket (branch $BRANCH)}"
done
echo "  3) cole o texto de $REL/PR.md na descrição"
if [ "$TEM_PRINTS" -eq 1 ]; then echo "  4) arraste os prints de $REL/prints/ na descrição (ou num comentário) e tire o [WIP] do título"; fi
echo "  Se o seu Bitbucket não oferecer PR como rascunho, comece o título com [WIP] até anexar os prints."
```

- [ ] **Step 6: Rodar os testes**

```bash
chmod +x script/pr.sh script/testes/pr_test.sh
bash script/testes/comum_test.sh   # esperado: ✔ incluindo os 3 link_pr
bash script/testes/pr_test.sh      # esperado: ✔, exit 0
```

- [ ] **Step 7: Commit**

```bash
./script/testar-kit.sh && git add script docs/modelos && git commit -m "feat: pr.sh monta o PR.md com resumo, prints e verificação

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 7: Padrões de desenvolvimento — `CLAUDE.md` (back e front), `settings.json` e a ficha

**Files:**
- Create: `CLAUDE.md` (api), `.claude/settings.json` (api), `docs/modelos/ficha-funcionalidade.md` (api), `CLAUDE.md` (web, em `$WEB`)
- Modify: `script/testar-kit.sh` (valida o JSON do `settings.json`)

**Interfaces:**
- Consumes: os scripts das Tarefas 2-6 (citados por nome), os arquivos reais de exemplo citados em crases (`testar-kit.sh` confere que existem), `docs/guia-operacao.pdf` (já commitado).
- Produces: `CLAUDE.md` do `lunna-api` (carregado sempre que o Claude Code abre em `lunna-api`; manda ler o do front), `CLAUDE.md` do `lunna-web`, `.claude/settings.json` com `permissions.additionalDirectories: ["../lunna-web"]`, e o modelo de ficha copiado pela skill `lunna-nova-funcionalidade` (Tarefa 8).

- [ ] **Step 1: Criar `CLAUDE.md` do `lunna-api`** (≤ 150 linhas)

````markdown
# Lunna — guia do Claude Code (back e fluxo do kit)

O Lunna é um painel SaaS de anúncios do Mercado Livre (multi-empresa). Este repositório é a **API** (`lunna-api`: Ruby 3.3, Rails 8.1 em modo API, PostgreSQL 16, Solid Queue) e a **base do kit de desenvolvimento**. O front é o `lunna-web` (`../lunna-web`, Nuxt 4): **leia `../lunna-web/CLAUDE.md` antes de mexer em qualquer arquivo dele**.

Quem trabalha aqui conhece o Mercado Livre e pouco de código. Fale em português simples, diga o que vai fazer antes de fazer, faça uma pergunta por vez e nunca peça que a pessoa leia código para decidir algo de negócio. Na dúvida sobre segurança ou produção, pare e peça ao dono do projeto.

## Fluxo de uma funcionalidade (siga a ordem)

1. `/lunna-nova-funcionalidade`: entrevista com a ficha (`docs/modelos/ficha-funcionalidade.md`), branch (`./script/nova-branch.sh`), testes primeiro, código.
2. `/lunna-verificar`: `./script/verificar.sh tudo` precisa ficar verde.
3. `/lunna-prints`: obrigatório quando a mudança altera tela (`./script/prints.sh`).
4. `/lunna-pr`: `./script/pr.sh` gera `evidencias/<branch>/PR.md`; a pessoa envia a branch, abre o PR e arrasta os prints.

Também: `/lunna-api-mercado-livre` (que dado ou endpoint do ML existe) e `/lunna-corrigir-bug`. Ambiente: `./script/dev-up.sh` (login demo `demo@lunna.dev` / `lunna12345`) e `./script/dev-down.sh`. Guia da pessoa: `docs/guia-operacao.pdf`. Quem implementa aqui **não faz deploy, não faz push na `main` e não mexe em segredos**.

## Regras de ouro (nunca quebre)

1. **Somente leitura no Mercado Livre.** O único POST ao ML é `/oauth/token`. Nada de `PUT`/`POST`/`DELETE` em anúncios, pedidos etc.
2. **Tudo escopado por empresa.** Toda leitura parte de `Current.company` e da conta (`Current.account`, via o concern `CurrentAccount`). Nunca `MlItem.find` direto, nunca `company_id` vindo de parâmetro; anúncio de outra empresa é 404.
3. **Regra de negócio só no back** (`app/services`). O front só exibe.
4. **Parâmetros de negócio por empresa** (imposto, margem mínima, cortes da Curva ABC): nunca fixos no código.
5. **Segredos nunca** em código, log, resposta, print ou PR (`ML_CLIENT_SECRET`, tokens, chave da OpenRouter).
6. **Não invente campos da API do ML.** Só os já documentados em `docs/SPEC.md` (seção 3); um novo exige resposta real salva como fixture.
7. **Teste junto com o código** e verificação verde antes de qualquer PR.
8. **Peça ao dono** antes de mexer em `cd/prod/`, `.env*`, `docs/DECISOES.md`, migrations que apagam dados, dependências novas ou qualquer deploy.

## Onde as coisas ficam

| O quê | Onde | Exemplo real |
|---|---|---|
| Rotas | `config/routes.rb` | |
| Controller (fino) | `app/controllers/` | `app/controllers/painel_controller.rb` |
| Escopo por conta e empresa | concern | `app/controllers/concerns/current_account.rb` |
| Formato das respostas e dos erros | concerns | `app/controllers/concerns/payloads.rb`, `app/controllers/concerns/error_rendering.rb` |
| Regra de negócio | `app/services/<dominio>/` | `app/services/painel/alerts.rb`, `app/services/abc/suggestion_engine.rb` |
| Chamadas ao Mercado Livre | um cliente só | `app/services/ml/client.rb` |
| Sincronização (etapas) | `app/services/ml/sync/` | |
| Trabalho em segundo plano | `app/jobs/` | `app/jobs/ai/action_plan_job.rb` |
| Modelos e banco | `app/models/`, `db/migrate/`, `db/schema.rb` | `app/models/ai_plan.rb` |
| Testes | `spec/` | `spec/requests/ai_plans_spec.rb`, `spec/services/ml/sync/run_spec.rb` |
| Respostas reais do ML | `spec/fixtures/ml/` | |
| Especificação | `docs/SPEC.md` (original), `docs/DECISOES.md` (prevalece), `docs/METRICS.md` | |

## Receitas

- **Endpoint novo:** rota em `config/routes.rb`; controller fino com `include CurrentAccount` quando lê por conta; resposta montada com os helpers de `payloads.rb`; erros como `{errors: [...]}`; request spec (200, 404 de outra empresa, 401 sem login).
- **Cálculo, alerta ou sugestão novos:** serviço em `app/services/<dominio>/` (`def self.call(...) = new(...).call`), spec com **os números da ficha**, incluindo os casos que não entram (exemplo: `app/services/painel/alerts.rb`).
- **Dado novo do ML:** use `/lunna-api-mercado-livre`. Método em `app/services/ml/client.rb`, etapa em `app/services/ml/sync/`, fixture real, WebMock. Falha parcial vira nota da sincronização; nunca derruba a rodada.
- **Migration:** reversível, `uuid` como chave, FK com `on_delete: :cascade` quando pertencer à conta, atualizar `db/schema.rb`.
- **Trabalho demorado:** job em `app/jobs/` com o resultado gravado no banco e lido por polling; nada longo dentro do request (exemplo: `app/jobs/ai/action_plan_job.rb`; ver `docs/DECISOES.md`, seção 10.1).
- **Texto para o usuário:** sempre em português.

## O que exige teste

| Mudança | Teste mínimo |
|---|---|
| Endpoint novo | request spec: sucesso, outra empresa (404), sem login (401) |
| Regra, cálculo, alerta | spec do serviço com os exemplos da ficha (entra, não entra, limite) |
| Chamada ao ML | fixture real + WebMock; caso de erro (403/404/500) |
| Job | spec do job: sucesso, erro tratado, cancelamento se houver |
| Migration | a suíte inteira roda com o `db/schema.rb` novo |

Nenhum teste chama o Mercado Livre nem a OpenRouter de verdade (WebMock). Rodar um arquivo só: `docker compose run --rm -T -e RAILS_ENV=test api bundle exec rspec spec/caminho_spec.rb`. Tudo de uma vez: `./script/verificar.sh api`.

## Peça ao dono do projeto antes de

Deploy e tudo em `cd/prod/`; arquivos `.env*` e o arquivo de segredos do servidor; configuração do app no DevCenter do Mercado Livre; `docs/DECISOES.md`; bibliotecas novas; migrations que apagam dados; qualquer push na `main`. Se o pedido da pessoa exigir uma dessas coisas, explique por quê e pare.
````

- [ ] **Step 2: Criar `.claude/settings.json` e a ficha `docs/modelos/ficha-funcionalidade.md`**

`.claude/settings.json`:

```json
{
  "permissions": {
    "additionalDirectories": ["../lunna-web"]
  }
}
```

`docs/modelos/ficha-funcionalidade.md`:

````markdown
# Ficha da funcionalidade

> Preencha em conversa com o Claude (`/lunna-nova-funcionalidade`). Escreva em termos de Mercado Livre; não precisa saber de código. Um exemplo com números vale mais que uma explicação longa.

**Nome curto:**

## 1. O que você quer ver

(Tela, tabela, coluna ou alerta. E por quê: que decisão isso ajuda a tomar?)

## 2. De onde vem o dado

(Campo do Mercado Livre, se souber. Se não souber, escreva "não sei": o Claude procura em `docs/SPEC.md`.)

## 3. Como calcular, com exemplo numérico

Regra em uma frase:

| Caso | Dados do anúncio (entrada) | Deve entrar / aparecer? |
|---|---|---|
| A (entra) | | sim |
| B (não entra) | | não |
| C (no limite) | | |

Inclua pelo menos um caso que **não** entra e um caso no limite. Esses exemplos viram os testes.

## 4. Quem vê

- [ ] administradores
- [ ] membros

## 5. Critério de aceite

- Com os casos acima, ...
- ...

## 6. O que não pode mudar

(O que já funciona e não pode ser alterado por esta funcionalidade.)

## 7. Mudança visual?

- [ ] sim (prints obrigatórios: claro, escuro e celular)
- [ ] não
````

- [ ] **Step 3: Criar `CLAUDE.md` do `lunna-web`** (em `$WEB`, ≤ 150 linhas)

````markdown
# lunna-web — guia do Claude Code (front)

Front do Lunna (Nuxt 4 + TypeScript, SSR). Consome a `lunna-api` (`../lunna-api`) e **não calcula nada**: métricas, alertas, Curva ABC, filtros, ordenação e paginação vêm prontos da API. As regras de ouro e o fluxo (skills `/lunna-*`, scripts `./script/*`) estão em `../lunna-api/CLAUDE.md`; a sessão do Claude Code deve ser aberta na pasta `lunna-api`, com este projeto como pasta adicional.

## Regras deste projeto

1. **Só exibe.** Nada de fórmula, filtro ou ordenação de negócio aqui: se a tela precisa de um número novo, ele vem da API.
2. **Formatação** (R$, números pt-BR, datas, percentuais) só por `app/lib/format.ts`.
3. **Cores só por tokens** de `app/assets/css/tokens.css` (tema claro e escuro). Estados (`ok`/`warn`/`bad`, `up`/`down`) chegam prontos da API; a tela só escolhe a cor.
4. **Sem segredos** no front: nada de chave ou token além do cookie de sessão que o próprio app já gerencia.
5. **Demorou? Polling.** Qualquer coisa demorada é acompanhada por consulta periódica, nunca por conexão longa (exemplo: `app/lib/aiPlanRunner.ts`).
6. **Texto de tela em português**, com acentuação correta.

## Camadas e onde ficam

| Camada | Onde | Exemplo real |
|---|---|---|
| Cliente HTTP puro (recebe o `$api`) | `app/lib/*Client.ts` | `app/lib/painelClient.ts`, `app/lib/aiPlanClient.ts` |
| Lógica pura testável | `app/lib/` | `app/lib/aiPlanRunner.ts`, `app/lib/apiErrors.ts` |
| Estado e ligação com o Nuxt | `app/composables/` | `app/composables/useAiPlan.ts`, `app/composables/usePolling.ts` |
| Componentes | `app/components/<area>/` | `app/components/painel/AlertsList.vue`, `app/components/abc/AiPlanPanel.vue` |
| Páginas (rotas) | `app/pages/` | `app/pages/index.vue`, `app/pages/anuncios.vue`, `app/pages/curva-abc.vue` |
| Sessão e conta selecionada | store Pinia | `app/stores/session.ts` |
| Tipos das respostas da API | `app/types/` | `app/types/painel.ts` |
| Plugin do `$api` (Bearer, 401 → login) | `app/plugins/` | `app/plugins/api.ts` |

## Receitas

- **Coluna, cartão ou alerta novo numa tela existente:** o dado novo entra no tipo (`app/types/painel.ts`), o componente só o mostra, a formatação vem de `app/lib/format.ts`. Teste do componente ao lado (`*.test.ts`).
- **Tela nova:** página em `app/pages/`, componentes em `app/components/<area>/`, item no menu (`app/app.vue`), teste; **prints obrigatórios** (claro, escuro e celular de 360 px).
- **Chamada nova à API:** função no cliente (`app/lib/*Client.ts`) + teste com um `$api` falso (exemplo: `app/lib/painelClient.test.ts`).
- **Ação demorada:** cliente + módulo puro de polling testado com timers falsos (exemplo: `app/lib/aiPlanRunner.test.ts`) + composable fino.
- **Tema:** claro, escuro e sistema já funcionam por tokens; confira as duas cores em todo componente novo.

## O que exige teste

| Mudança | Teste mínimo |
|---|---|
| Função em `app/lib/` | Vitest ao lado, cobrindo o erro e o vazio |
| Componente com regra de exibição | montar com `@vue/test-utils` e conferir texto e estados |
| Composable com assíncrono | lógica no módulo puro (`app/lib/`) e teste com timers falsos |
| Qualquer tela mudada | prints (`./script/prints.sh`, rodado no `lunna-api`) |

## Comandos (Node 22)

`npm run test` (Vitest), `npm run typecheck`, `npm run lint`, `npm run dev` (porta 3101). Para rodar tudo junto com o back, use `./script/verificar.sh tudo` no `lunna-api`. Não adicione bibliotecas sem o dono.
````

- [ ] **Step 4: Acrescentar a checagem do JSON ao `script/testar-kit.sh`** (antes do `echo` final, dentro da seção "Guias e skills")

```bash
if [ -f .claude/settings.json ] && command -v python3 >/dev/null 2>&1; then
  checar ".claude/settings.json é JSON válido" python3 -c "import json; json.load(open('.claude/settings.json'))"
fi
```

- [ ] **Step 5: Rodar `testar-kit.sh`**

Run: `./script/testar-kit.sh`
Expected: `✔ CLAUDE.md: <N> linhas (máx. 150)`, `✔ caminhos citados em CLAUDE.md existem`, o mesmo para `$WEB/CLAUDE.md`, `✔ .claude/settings.json é JSON válido`, e `✔ Kit em ordem.` Se algum caminho citado não existir, o `✘` diz qual: corrija o texto (não crie arquivo só para passar).

- [ ] **Step 6: Commit nos dois repos**

```bash
git add CLAUDE.md .claude/settings.json docs/modelos/ficha-funcionalidade.md script/testar-kit.sh
git commit -m "docs: CLAUDE.md do back com as regras de ouro e o fluxo, ficha da funcionalidade

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
git -C "$WEB" add CLAUDE.md
git -C "$WEB" commit -m "docs: CLAUDE.md do front com o padrão de desenvolvimento

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 8: As 6 skills

**Files:**
- Create: `.claude/skills/lunna-nova-funcionalidade/SKILL.md`, `.claude/skills/lunna-api-mercado-livre/SKILL.md`, `.claude/skills/lunna-verificar/SKILL.md`, `.claude/skills/lunna-prints/SKILL.md`, `.claude/skills/lunna-pr/SKILL.md`, `.claude/skills/lunna-corrigir-bug/SKILL.md`

**Interfaces:**
- Consumes: os scripts e o `CLAUDE.md` das tarefas anteriores; `testar-kit.sh` valida frontmatter (`name`, `description`), ≤ 150 linhas e os caminhos citados.
- Produces: comandos `/lunna-nova-funcionalidade`, `/lunna-api-mercado-livre`, `/lunna-verificar`, `/lunna-prints`, `/lunna-pr`, `/lunna-corrigir-bug` (o `name` de cada `SKILL.md` é igual ao nome da pasta).

- [ ] **Step 1: `lunna-nova-funcionalidade`**

````markdown
---
name: lunna-nova-funcionalidade
description: Use quando a pessoa quiser criar uma funcionalidade nova no Lunna (tela, alerta, coluna, métrica, cálculo, filtro) ou mudar o comportamento de algo que já existe. Conduz o fluxo inteiro em português simples - ficha em linguagem de Mercado Livre, branch, testes primeiro, código no back e no front, verificação, prints e PR.
---

# Nova funcionalidade no Lunna

Você conduz uma pessoa que **conhece o Mercado Livre e pouco de código**. Português simples, uma pergunta por vez, explique antes de agir. Leia `CLAUDE.md` e `../lunna-web/CLAUDE.md` antes de escrever código.

## 1. Preparar
- O ambiente precisa estar no ar: se `http://localhost:3101` não responder, rode `./script/dev-up.sh`.
- Veja `git status` nos dois projetos. Se houver trabalho pendente, pergunte se ela termina ou descarta (nunca descarte sozinho).

## 2. Entrevista (a ficha)
Crie `evidencias/<branch>/ficha.md` a partir de `docs/modelos/ficha-funcionalidade.md` (use um nome provisório de pasta se a branch ainda não existir; mova depois) e preencha **em conversa**, uma seção por vez:
1. O que ela quer ver e por quê (que decisão isso ajuda a tomar).
2. De onde vem o dado. "Não sei" é resposta válida: você procura em `docs/SPEC.md`.
3. Como calcular, **com exemplo numérico**. Insista em pelo menos **um caso que não entra** e um caso no limite: eles viram os testes.
4. Quem vê (administrador, membro ou ambos).
5. Critério de aceite ("dado X ⇒ aparece Y").
6. O que não pode mudar.
7. Se é mudança visual (então haverá prints).

## 3. Conferir a ficha antes de qualquer código
Escreva em até 5 linhas e peça o **"sim" da pessoa**:
- O que já existe parecido? (procure no código, por exemplo `app/services/painel/alerts.rb`).
- Que dado do ML alimenta? Já é sincronizado? Se precisar de dado novo, use `/lunna-api-mercado-livre`; se exigir permissão nova no DevCenter, **pare** e avise que é do dono.
- Passa nas regras de ouro do `CLAUDE.md` (somente leitura, por empresa, regra no back, sem segredo)? Se não, explique por quê e proponha outra forma.
- Quais arquivos mudam no back e no front?

## 4. Branch
`./script/nova-branch.sh "<nome da funcionalidade>"` cria `feature/<nome>` nos dois projetos. Se recusar, leia a mensagem e resolva antes de seguir.

## 5. Testes primeiro
Transforme os casos da ficha em testes que **falham pelo motivo certo**:
- Back: spec do serviço ou endpoint (receitas no `CLAUDE.md`). Rode `docker compose run --rm -T -e RAILS_ENV=test api bundle exec rspec <arquivo>` e mostre a falha.
- Front: teste Vitest ao lado do código (`../lunna-web/CLAUDE.md`). Rode `npm run test -- <arquivo>` em `lunna-web` com Node 22.

## 6. Implementar
Back primeiro (regra e endpoint), depois o front (só exibição). Faça a menor mudança que passa nos testes e siga os padrões dos dois `CLAUDE.md`. Commits pequenos, em português (`feat:`, `fix:`), com as linhas de atribuição que o Claude Code indicar. Nunca faça push na `main` nem deploy.

## 7. Fechar
1. `/lunna-verificar` (precisa ficar verde).
2. Se mexeu em tela: `/lunna-prints`.
3. `/lunna-pr`.
Explique o que a pessoa faz agora (enviar a branch e abrir o PR). Só faça o push se ela pedir.

## Pare e chame o dono quando
- A ficha exigir escrever no ML, dado de outra empresa, ou dado que não existe na API do ML.
- Precisar mexer em `cd/prod/`, `.env*`, `docs/DECISOES.md`, dependências novas ou migration que apaga dados.
- Os testes existentes quebrarem por um motivo que você não entende depois de duas tentativas.
````

- [ ] **Step 2: `lunna-api-mercado-livre`**

````markdown
---
name: lunna-api-mercado-livre
description: Use quando a pessoa perguntar que dado, campo ou endpoint do Mercado Livre o Lunna usa ou pode usar, ou quiser propor um dado novo do ML. Explica o mapa dos endpoints já sincronizados e o passo a passo seguro (somente leitura, exemplo real como fixture, permissão do DevCenter).
---

# API do Mercado Livre no Lunna

O Lunna **só lê** o ML (o único POST é o `/oauth/token`). Todas as chamadas passam por `app/services/ml/client.rb`, e as etapas de sincronização ficam em `app/services/ml/sync/`.

## O que já é sincronizado

| Dado | Endpoint (GET) | Método em `Ml::Client` | Frequência |
|---|---|---|---|
| Conta | `/users/me` | `me` | ao conectar |
| IDs dos anúncios | `/users/{seller}/items/search` (scan) | `items_scan` | 5 min |
| Dados dos anúncios | `/items?ids=` (20 por vez) | `items_multiget` | 5 min |
| Pedidos | `/orders/search` | `orders_search` | 5 min (62 dias na 1ª vez, depois 4 dias) |
| Visitas (60 dias) | `/items/{id}/visits/time_window` | `item_visits` | 30 min |
| Qualidade | `/item/{id}/performance` | `item_performance` | 6 h (anúncio de catálogo não suporta) |
| Descrição | `/items/{id}/description` | `item_description` | 12 h |
| Atributos da categoria | `/categories/{id}/attributes` | `category_attributes` | 12 h |
| Preço promocional | `/items/{id}/sale_price` | `item_sale_price` | 12 h |
| Tarifa de venda | `/sites/MLB/listing_prices` | `listing_prices` | 12 h |
| Frete pago pelo vendedor | `/users/{seller}/shipping_options/free` | `shipping_free` | 12 h |
| Referência de preço e concorrentes | `/suggestions/items/{id}/details` | `price_suggestion` | 12 h |

Os campos guardados estão nas colunas de `ml_items` em `db/schema.rb`; a descrição completa de cada endpoint está em `docs/SPEC.md` (seção 3). **Antes de propor um dado novo, veja se ele já está no banco.**

## Propor um dado novo (nesta ordem)
1. **Já existe?** Procure em `app/services/ml/client.rb`, nas colunas de `ml_items` (`db/schema.rb`) e nos arquivos de `spec/fixtures/ml/`.
2. **Confirme na documentação oficial** (developers.mercadolivre.com.br). Algumas ferramentas recebem 403 nessas páginas; `curl -sL -A 'Mozilla/5.0' <url>` costuma funcionar. **Não invente campo**: se não achar, diga que não achou.
3. **Só `GET`.** Se o endpoint exigir `POST`, `PUT` ou `DELETE`, pare: é escrita e o Lunna não faz.
4. **Permissão.** O app do DevCenter está só em **Leitura** (Usuários, Publicação e sincronização, Venda e envios, Métricas do negócio). Endpoint de outro grupo dá 403: quem libera é o dono.
5. **Exemplo real.** Peça ao dono uma resposta real (ou capture uma no ambiente dele), remova dados pessoais e tokens e salve em `spec/fixtures/ml/<nome>.json`. O teste usa essa fixture, nunca a API de verdade.
6. **Implemente:** método em `Ml::Client`, etapa em `app/services/ml/sync/` (falha parcial vira nota e a rodada segue; carimbe a data mesmo em erro para não repetir em loop) e spec com WebMock.
7. Peça ao dono para registrar o endpoint em `docs/SPEC.md` (a pessoa não edita esse arquivo de decisões).

Depois siga o fluxo normal: `/lunna-verificar`, `/lunna-pr`.
````

- [ ] **Step 3: `lunna-verificar`**

````markdown
---
name: lunna-verificar
description: Use antes de abrir um PR ou quando a pessoa perguntar se está tudo certo. Roda a verificação completa (testes, estilo e segurança do back; tipos, estilo e testes do front), explica cada falha em português simples e corrige.
---

# Verificar antes do PR

1. Rode `./script/verificar.sh tudo` (ou `api` / `web` para acelerar). Leva alguns minutos; avise a pessoa.
2. **Tudo ✔:** diga "está verde" e cite o resumo (quantos testes). Siga para `/lunna-prints` (se houve mudança de tela) ou `/lunna-pr`.
3. **Algum ✘:** o script imprime o caminho do log em `evidencias/<branch>/verificacao-*.txt`. Leia a parte da falha (procure `Failures:` para os testes do back e `FAIL` para o Vitest) e explique à pessoa **em uma frase, sem jargão**, o que quebrou.
4. Corrija a **causa**, não o sintoma. Em falha de teste, entenda primeiro se o teste ou o código está errado; nunca apague nem enfraqueça um teste para ficar verde.
5. Rode de novo só a parte que falhou (`./script/verificar.sh api` ou `web`) e depois `./script/verificar.sh tudo` para confirmar.

## Dicas por parte
- **Estilo do back (RuboCop):** `docker compose run --rm -T api bundle exec rubocop -a` corrige o que é seguro automaticamente; revise o diff.
- **Segurança (Brakeman):** o aviso aponta arquivo e linha; corrija o código, não silencie o aviso sem falar com o dono.
- **Bibliotecas (bundler-audit):** precisa de internet. Se apontar uma biblioteca vulnerável, **não atualize sozinho**: avise o dono.
- **Tipos e estilo do front:** `npm run typecheck` e `npm run lint` em `lunna-web` (Node 22) dão a mensagem completa.

## Pare e chame o dono se
Duas tentativas seguidas de correção não resolverem, ou se a correção pedir mexer em `cd/prod/`, `.env*`, `docs/DECISOES.md` ou dependências. Mostre o arquivo de log.
````

- [ ] **Step 4: `lunna-prints`**

````markdown
---
name: lunna-prints
description: Use quando a mudança altera o que aparece na tela (tela nova, coluna, alerta, cor, texto). Gera os prints numerados em claro, escuro e celular com o login demo e confere cada imagem antes de ir para o PR.
---

# Prints da mudança

Toda mudança **visual** precisa de prints no PR. Mudança sem tela não precisa.

1. O ambiente precisa estar no ar (`./script/dev-up.sh`).
2. Se a funcionalidade tem telas próprias, crie `evidencias/<branch>/roteiro.json` com as cenas do roteiro base (`script/prints/roteiros/base.json`) **e** as novas. Cada cena tem `nome`, `rota`, `esperar` (um texto ou seletor que **precisa** aparecer, senão a cena falha) e, se preciso, `acoes`:
   ```json
   { "cenas": [ { "nome": "alerta-preco", "rota": "/", "esperar": "text=Preço acima da referência do ML" } ] }
   ```
   Ações aceitas: `{"clicar": "seletor"}`, `{"esperar": "seletor"}`, `{"digitar": {"seletor": "...", "texto": "..."}}`, `{"rolar": 600}`. `"login": false` para telas públicas e `"paginaInteira": true` para a página toda.
3. Rode `./script/prints.sh`. Ele confere o dono real da porta 3101, faz o build de produção do front, entra com o login demo e salva `evidencias/<branch>/prints/NN-<cena>-<claro|escuro|mobile>.png`.
4. **Abra cada imagem** (ferramenta de leitura de imagens) e confira:
   - aparece o que a pessoa pediu, com os números do exemplo da ficha;
   - texto em português correto, sem corte, sem sobreposição;
   - tema escuro legível e celular (360 px) sem rolagem horizontal quebrada;
   - **nenhum dado real ou secreto** (o ambiente demo é fictício; se aparecer e-mail, token ou chave reais, pare e avise o dono).
5. Se algo estiver errado, corrija o código e gere de novo (o script apaga os prints anteriores).
6. Diga à pessoa quantos prints saíram e onde estão; ela vai arrastá-los no PR (`/lunna-pr` explica).

## Se o script recusar
- "Porta 3101 de outro projeto": há outro projeto usando a porta; a pessoa encerra esse projeto. **Nunca** force nem mate o processo alheio.
- "A API não está no ar": `./script/dev-up.sh`.
- Cena com ✘: o `esperar` do roteiro não apareceu; confira a tela em `http://localhost:3101` e ajuste o seletor ou o código.
````

- [ ] **Step 5: `lunna-pr`**

````markdown
---
name: lunna-pr
description: Use quando a pessoa quiser abrir o PR ou entregar o trabalho para revisão. Escreve o resumo em linguagem de negócio, gera o texto do PR com os prints e o resultado da verificação, e explica passo a passo como enviar a branch e abrir o PR no Bitbucket.
---

# Abrir o PR

Pré-requisitos: `/lunna-verificar` verde e, se houve mudança de tela, `/lunna-prints`. O trabalho precisa estar em **commits** (o que está só na pasta não entra no PR).

1. Confira `git status` nos dois projetos. Se houver alteração sem commit, pergunte se pode commitar (mensagem em português, com as linhas de atribuição indicadas pelo Claude Code).
2. Escreva em `evidencias/<branch>/` (crie a pasta se faltar):
   - `resumo.md`: 3 a 6 linhas, **linguagem de negócio**: o que muda para o vendedor e por quê. Sem nome de arquivo nem jargão.
   - `como-testar.md`: passos numerados com o login demo (`demo@lunna.dev` / `lunna12345`) e onde clicar.
   - `titulo.txt`: uma linha, até 70 caracteres, no imperativo ("Alerta de preço acima da referência").
   Mostre à pessoa e ajuste com o que ela disser.
3. Rode `./script/pr.sh`. Se ele recusar (sem verificação, sem prints, na `main`, sem commits), resolva o motivo e rode de novo.
4. Abra `evidencias/<branch>/PR.md`, confira cada item do checklist das regras de ouro contra o que foi feito e troque `- [ ]` por `- [x]` **só nos que forem verdadeiros**. Se algum for falso, corrija o código antes.
5. Explique à pessoa, um passo por vez:
   1. enviar a branch de cada projeto (o script imprime o comando `git push -u origin feature/...`; só rode se ela pedir);
   2. abrir o PR pelo link que o script imprimiu, colar o texto do `PR.md` na descrição;
   3. arrastar os prints de `evidencias/<branch>/prints/` para a descrição ou um comentário (o Bitbucket não recebe imagem por script) e tirar o `[WIP]` do título, se usou;
   4. avisar o dono do projeto: ele revisa, faz o merge e o deploy.
6. Funcionalidade que mexeu no back **e** no front gera dois PRs, um por projeto, com o mesmo texto.

Nunca faça push na `main`, nunca faça o merge e nunca faça deploy.
````

- [ ] **Step 6: `lunna-corrigir-bug`**

````markdown
---
name: lunna-corrigir-bug
description: Use quando a pessoa disser que algo está errado, quebrado ou com número diferente do esperado no Lunna. Reproduz o problema com um teste que falha, encontra a causa raiz, corrige, verifica e prepara o PR.
---

# Corrigir um bug

Português simples, uma pergunta por vez. Leia `CLAUDE.md` (e `../lunna-web/CLAUDE.md` se for de tela).

1. **Entender:** o que ela esperava ver, o que viu, em qual tela e com qual anúncio ou dado. Peça um exemplo com números. Se o problema só acontece com dados reais, peça ao dono uma resposta real do ML (sem tokens) para virar fixture.
2. **Reproduzir:** rode `./script/dev-up.sh` e tente ver o problema na tela. Depois escreva **um teste que falha pelo motivo certo** (spec no back, Vitest no front). Sem teste falhando você ainda não entendeu o bug.
3. **Causa raiz, não sintoma:** siga o fluxo de ponta a ponta (tela, cliente, endpoint, serviço, dado) e procure quem mais usa a mesma função antes de mexer. Se a regra está no back, corrija no back (o front só exibe).
4. **Corrigir** no ponto compartilhado, com a menor mudança que faz o teste passar. Crie a branch com `./script/nova-branch.sh "corrige <assunto>"` antes de editar.
5. **Verificar:** `/lunna-verificar`. Mudança de tela: `/lunna-prints`.
6. **PR:** `/lunna-pr`, com o resumo dizendo **o que estava errado e o que passa a acontecer**.

## Pare e chame o dono se
O bug envolver dado de outra empresa vazando, segredo exposto, escrita no ML, produção fora do ar ou perda de dados. Não tente corrigir sozinho: descreva o que viu.
````

- [ ] **Step 7: Rodar `testar-kit.sh` e commitar**

```bash
./script/testar-kit.sh
```
Expected: cada `SKILL.md` com `✔ (máx. 150)`, `✔ … tem name e description`, `✔ caminhos citados … existem` e `✔ Kit em ordem.`

```bash
git add .claude/skills
git commit -m "feat: seis skills lunna-* para conduzir o desenvolvimento

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

---

### Task 9: README do DevCenter, guia final em PDF e exercício de ponta a ponta

**Files:**
- Modify: `README.md` (api), `docs/guia-operacao.html`, `docs/guia-operacao.pdf`

**Interfaces:**
- Consumes: tudo das Tarefas 1-8; a saída real dos scripts; o `claude` CLI (para conferir que as skills carregam).
- Produces: README correto, guia de operação v1.0 com a saída real dos comandos, e a evidência de que o fluxo completo funciona sem push.

- [ ] **Step 1: Corrigir o trecho do DevCenter no `README.md` do `lunna-api`**

Trocar (Edit exato) os itens 3 e 4 da lista "Configurar o app no DevCenter do Mercado Livre":

```
3. **Permissões**: leitura e escrita (a escrita fica reservada para funções futuras) e **`offline_access`**
   — sem ele o ML não devolve `refresh_token` e a conexão é recusada (`sem_offline_access`).
4. Copie o **Client ID** e o **Client Secret** para `ML_CLIENT_ID` e `ML_CLIENT_SECRET`. É a única
   configuração global do ML: cada empresa conecta as próprias contas em Configurações › Contas.
```

por:

```
3. **Fluxos OAuth**: marque **Authorization Code** e **Refresh Token** (é o que entrega o `refresh_token`; sem
   ele a conexão é recusada com `sem_offline_access`). Deixe o **PKCE desligado** (o Lunna não o usa) e não
   marque Client Credentials.
4. **Permissões**, todas em **Leitura** (o Lunna nunca escreve no ML): Usuários, Publicação e sincronização,
   Venda e envios de um produto e Métricas do negócio. As demais ficam em "Sem acesso". Negócio: só Mercado Livre.
5. **Notificações**: sem tópicos. Se o campo da URL for obrigatório, use `<API_URL>/webhooks/ml` (responde 200 e
   ignora o conteúdo).
6. Copie o **Client ID** e o **Client Secret** para `ML_CLIENT_ID` e `ML_CLIENT_SECRET`. É a única
   configuração global do ML: cada empresa conecta as próprias contas em Configurações › Contas.
```

E inserir, antes da seção `## Variáveis de ambiente`:

```
## Desenvolvendo com o kit (para quem não é de desenvolvimento)

Skills, scripts e guia para criar funcionalidades com segurança: leia `docs/guia-operacao.pdf`, rode
`./script/setup.sh` uma vez e abra o Claude Code nesta pasta (o front entra como pasta adicional). O fluxo é
`/lunna-nova-funcionalidade` → `/lunna-verificar` → `/lunna-prints` → `/lunna-pr`. Regras e padrões em
`CLAUDE.md`; scripts em `script/` (`./script/testar-kit.sh` testa o próprio kit).
```

- [ ] **Step 2: Exercício de ponta a ponta em clones descartáveis (sem push)**

Os scripts do kit só existem na branch `feature/kit-desenvolvimento`; por isso os clones de teste têm a `main` **do origin local** apontada para essa branch (não toca no Bitbucket).

```bash
E2E=/tmp/kit-e2e; rm -rf "$E2E"; mkdir -p "$E2E"
for r in api web; do
  if [ "$r" = api ]; then src="$API"; else src="$WEB"; fi
  git clone -q --bare "$src" "$E2E/$r-origin.git"
  git -C "$E2E/$r-origin.git" branch -f main feature/kit-desenvolvimento
  git clone -q "$E2E/$r-origin.git" "$E2E/lunna-$r"
done
unset LUNNA_API_DIR; export WEB_DIR="$E2E/lunna-web"; cd "$E2E/lunna-api"
./script/dev-down.sh || true        # garante as portas 3100/3101 livres
./script/setup.sh                   # esperado: todos ✔, ".env criado", npm ci nos dois lugares
./script/dev-up.sh                  # esperado: "Tudo no ar." e o login demo
./script/nova-branch.sh "Exercício do kit"     # esperado: feature/exercicio-do-kit nos dois repos
```

Teste primeiro (vermelho) no front, depois a mudança (verde):

```bash
python3 - <<'EOF'
import pathlib
p = pathlib.Path("/tmp/kit-e2e/lunna-web/app/pages/login.test.ts")
t = p.read_text(encoding="utf-8").rstrip()
assert t.endswith("})")
t = t[:-2].rstrip() + """

  it('mostra o aviso de ambiente de teste no subtítulo', () => {
    const wrapper = mountLogin(loginMock)
    expect(wrapper.text()).toContain('Acesse o painel dos seus anúncios do Mercado Livre (ambiente de teste).')
  })
})
"""
p.write_text(t, encoding="utf-8")
EOF
NODE22="$(ls -d ~/.nvm/versions/node/v22.* | sort -V | tail -1)/bin"
(cd "$WEB_DIR" && PATH="$NODE22:$PATH" npm run test -- app/pages/login.test.ts)      # esperado: FAIL no teste novo
sed -i 's/Acesse o painel dos seus anúncios do Mercado Livre\./Acesse o painel dos seus anúncios do Mercado Livre (ambiente de teste)./' "$WEB_DIR/app/pages/login.vue"
(cd "$WEB_DIR" && PATH="$NODE22:$PATH" npm run test -- app/pages/login.test.ts)      # esperado: PASS
git -C "$WEB_DIR" add -A && git -C "$WEB_DIR" commit -q -m "feat: subtítulo do login avisa que é ambiente de teste

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
```

Verificação, prints, texto do PR:

```bash
./script/verificar.sh tudo          # esperado: 7 linhas ✔ e "Tudo verde."
cp evidencias/feature-exercicio-do-kit/verificacao-resumo.txt /tmp/verificacao-resumo-real.txt   # usado no Step 4
mkdir -p evidencias/feature-exercicio-do-kit
cat > evidencias/feature-exercicio-do-kit/roteiro.json <<'EOF'
{ "cenas": [ { "nome": "login", "rota": "/login", "login": false, "esperar": "text=(ambiente de teste)" } ] }
EOF
./script/prints.sh                  # esperado: 3 prints (claro, escuro, mobile) da cena login
printf 'O texto abaixo do título da tela de entrada agora avisa que o ambiente é de teste.\n' > evidencias/feature-exercicio-do-kit/resumo.md
printf '1. Abra http://localhost:3101/login.\n2. Confira o subtítulo: "... do Mercado Livre (ambiente de teste)."\n' > evidencias/feature-exercicio-do-kit/como-testar.md
printf 'Avisar ambiente de teste no login\n' > evidencias/feature-exercicio-do-kit/titulo.txt
./script/pr.sh                      # esperado: PR.md criado + comando de push e link (ou aviso de origin local)
```

Conferir a olho (ferramenta de leitura de imagens) `evidencias/feature-exercicio-do-kit/prints/01-login-claro.png`: o subtítulo mostra "(ambiente de teste)". Conferir `evidencias/feature-exercicio-do-kit/PR.md`: título, resumo, prints legendados, verificação e checklist; `grep -c '{{' evidencias/feature-exercicio-do-kit/PR.md` → `0`.

Conferir que **nada foi enviado**: `git -C "$E2E/lunna-web" log --oneline origin/main..HEAD` mostra 1 commit e `git -C "$E2E/web-origin.git" branch` não tem `feature/exercicio-do-kit`.

O `$E2E` continua de pé para o Step 3; a limpeza fica no fim dele.

- [ ] **Step 3: Conferir que as skills carregam e que o front entra como pasta adicional (critérios 5 e 6 do spec)**

Antes do `rm -rf "$E2E"` (ou em outro clone igual), com o Claude Code aberto **na pasta do `lunna-api`**:

```bash
cd "$E2E/lunna-api"
claude -p "Liste, uma por linha e sem mais nada, os nomes das skills que começam com lunna- disponíveis nesta pasta." --output-format text
claude -p "Leia ../lunna-web/CLAUDE.md e responda somente com a primeira linha do arquivo." --output-format text
```
Expected: as 6 skills (`lunna-nova-funcionalidade`, `lunna-api-mercado-livre`, `lunna-verificar`, `lunna-prints`, `lunna-pr`, `lunna-corrigir-bug`) e a linha `# lunna-web — guia do Claude Code (front)`. Se a segunda chamada for negada, o `permissions.additionalDirectories` não foi respeitado: registre o resultado no spec (§14) e mantenha a instrução explícita de leitura que o `CLAUDE.md` já tem (o kit continua funcionando, pedindo autorização de leitura uma vez).

Limpar o exercício: `./script/dev-down.sh; cd "$API"; unset WEB_DIR; export WEB_DIR="$WEB"; rm -rf "$E2E"` (o arquivo `/tmp/verificacao-resumo-real.txt` fica para o Step 4).

- [ ] **Step 4: Regerar o guia de operação com a saída real e a versão 1.0**

Com a saída do `verificar.sh` do Step 2 (arquivo `evidencias/feature-exercicio-do-kit/verificacao-resumo.txt`, copiado antes de limpar):

```bash
python3 - /tmp/verificacao-resumo-real.txt <<'EOF'
import pathlib, re, sys
p = pathlib.Path("docs/guia-operacao.html")
html = p.read_text(encoding="utf-8")
linhas = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[1:]
bloco = "<pre>" + "\n".join(linhas) + "\nLog completo: evidencias/&lt;branch&gt;/verificacao-&lt;data&gt;.txt</pre>"
html, n1 = re.subn(r"(<p>O resultado sai como uma lista curta:</p>\s*)<pre>.*?</pre>", lambda m: m.group(1) + bloco, html, count=1, flags=re.S)
html, n2 = re.subn(r'<div class="note warn"><strong>Status desta versão\.</strong>.*?</div>',
    '<div class="note"><strong>Versão 1.0.</strong> Este guia descreve o kit como foi implementado; a saída dos comandos mostrada aqui é a real.</div>',
    html, count=1, flags=re.S)
html, n3 = re.subn(r"Versão 0\.1 · 25 de setembro de 2026", "Versão 1.0", html, count=1)
assert (n1, n2, n3) == (1, 1, 1), (n1, n2, n3)
p.write_text(html, encoding="utf-8")
EOF
cd docs && google-chrome --headless=new --no-sandbox --disable-gpu --no-pdf-header-footer --print-to-pdf=guia-operacao.pdf "file://$PWD/guia-operacao.html" && cd ..
pdftotext -layout docs/guia-operacao.pdf - | grep -c -i "rascunho"        # esperado: 0
pdfinfo docs/guia-operacao.pdf | grep Pages
```
Conferir também que a tabela de comandos do guia (seção 9) bate com o `--ajuda` de cada script (`./script/<nome>.sh --ajuda`) e acrescentar `--so-verificar` à linha do `setup.sh`. Ver as páginas alteradas (rasterizar com `pdftoppm -r 60`) e olhar o layout.

- [ ] **Step 5: Verificação final do kit, varredura de segredos e commits**

```bash
./script/testar-kit.sh --completo                                  # esperado: ✔ Kit em ordem.
git diff main...HEAD | grep -nE "sk-or-v1-[A-Za-z0-9]{10,}|BEGIN (RSA|OPENSSH) PRIVATE|ML_CLIENT_SECRET *= *[A-Za-z0-9]{8,}" || echo "sem segredos na api"
git -C "$WEB" diff main...HEAD | grep -nE "sk-or-v1-[A-Za-z0-9]{10,}|BEGIN (RSA|OPENSSH) PRIVATE" || echo "sem segredos no web"
git add README.md docs
git commit -m "docs: README com o DevCenter correto e o kit; guia de operação v1.0 com a saída real

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KDcjQ5QpKu5KjkqvAsTXtH"
git log --oneline main..HEAD; git -C "$WEB" log --oneline main..HEAD
```
Expected: os dois "sem segredos", e as listas de commits das duas branches. **Não fazer push nem abrir PR**: relatar ao dono os dois caminhos de branch, os critérios do spec §12 (com a evidência de cada um) e perguntar se quer os PRs.

---

## Self-review (feito contra o spec)

**Cobertura do spec:** §4 regras de ouro → Tarefa 7 (`CLAUDE.md`); §5 estrutura → Tarefas 1-9; §6 padrões → Tarefa 7; §7 skills → Tarefa 8; §8 ficha → Tarefa 7; §9 os oito scripts → Tarefas 1 (`testar-kit`), 2 (`setup`, `dev-up`, `dev-down`), 3 (`nova-branch`), 4 (`verificar`), 5 (`prints`), 6 (`pr`); §10 fluxo → skills + exercício da Tarefa 9; §11 casos de borda → portas (T2, T5), Docker sem rede (T2), teste falhando (T4), Chrome ausente (T2 e T5); §12 critérios: 1 (T2 + exercício), 2 (T4 lento), 3 (T5 lento), 4 (T6), 5 (T1 limites + T9 Step 3), 6 (T9 Step 3), 7 (T9 Step 5); §14 → README (T9), PR sem rascunho (`[WIP]` no T6), `@import`/diretório adicional (T9 Step 3). O guia em PDF (fase 3 do spec) fecha na Tarefa 9.

**Ordem:** difere das fases do spec porque `testar-kit.sh` confere que `CLAUDE.md` e skills só citam caminhos que existem: os documentos vêm depois dos scripts que citam.

**Placeholders:** nenhum. Cada passo traz o código ou o comando completo.

**Consistência de nomes:** `RAIZ_KIT`/`RAIZ_API`/`RAIZ_WEB`, `compose`, `com_node22`, `esperar_url`, `pasta_evidencias`, `slug_da_branch`, `estado_da_porta_api`/`estado_da_porta_web`, `subir_front_dev`, `desligar_front_da_porta`, `link_pr` e o formato `evidencias/<branch>/{verificacao-resumo.txt,prints/NN-<cena>-<claro|escuro|mobile>.png,resumo.md,como-testar.md,titulo.txt,PR.md}` são os mesmos em todas as tarefas.
