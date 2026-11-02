# Lunna API (Rails 8.1, modo API)

Back-end do Lunna, painel para vendedores do Mercado Livre. O front fica em `lunna-web`.

## Leia antes de mexer
- `docs/secoes/README.md`: um documento por item do menu (o que faz, dados, regras, arquivos). Ao mudar uma regra,
  atualize o documento da seção no mesmo commit.
- `.claude/skills/secao-*`: uma skill por seção (visão geral, produtos, anúncios, vendas, ads, curva ABC, radar, configurações)
  que aponta para o documento certo; use-as ao mexer em uma seção.
- `docs/DECISOES.md` prevalece sobre `docs/SPEC.md`. `docs/METRICS.md` define as métricas.

## Mapa de pastas
- `app/controllers/`: finos; só autenticam, escopam pela empresa e renderizam.
- `app/services/`: regras de negócio. `painel/` (visão geral, anúncios), `abc/`, `ml/` (leitura do Mercado Livre, incl. pedidos e envios da seção Vendas),
  `olist/` (ERP, custo PEPS, kits), `ai/`.
- `app/jobs/`: segundo plano (Solid Queue). Agenda em `config/recurring.yml`.
- `app/models/`: dados e validações.
- `spec/`: RSpec, WebMock e FactoryBot. Espelha a estrutura de `app/`.
- `lib/tasks/`: rake (`olist.rake`).

## Regras de ouro
1. Regra de negócio fica na API, nunca no front.
2. Parâmetros de negócio (imposto, margem, despesas fixas) são por empresa, nunca fixos no código.
3. Mercado Livre é somente leitura. Escrita no Olist só por administrador, com `confirm=true` e registro em `olist_changes`.
4. Tudo escopado por `Current.company`. Nunca consultar dados de outra empresa.
5. Segredos (`.env`, tokens) nunca entram no git nem em respostas/logs. Tokens são cifrados (Active Record Encryption).
6. A coleta do Radar acontece só por pedido do usuário; nada agendado.

## Comandos
- Subir: `docker compose up` (api na 3000, `jobs`, postgres). No Windows, a porta é publicada só em IPv4.
- Ruby 3.4.12 (Dockerfile e `.ruby-version`). As versões 3.3.12 e 3.3.10 derrubavam api e worker com `[BUG] Segmentation
  fault` / `cfp consistency error`; ao trocar de Ruby, rode `docker compose run --rm api bundle install` (o volume
  `gem_cache` guarda extensões nativas compiladas para a versão anterior).
- `BOOTSNAP_CACHE_DIR=/tmp/bootsnap` no compose: cada container (api, jobs) tem o próprio cache do bootsnap. Com o cache
  em `tmp/cache` da pasta montada do Windows, os dois gravando juntos corrompiam o bytecode (quedas com `[BUG]` e
  `NoMethodError` sem sentido dentro do Rails, mesmo no Ruby 3.4). Não volte o cache para a pasta montada.
- O serviço `jobs` roda `bin/jobs-watchdog`: sobe o Solid Queue e, se nenhum Worker der heartbeat por 5 minutos
  (`bin/jobs-heartbeat`), sai com erro para o Docker reiniciar (`restart: unless-stopped`).
- Testes: `docker compose run --rm -e RAILS_ENV=test api bash -c "bin/rails db:prepare && bundle exec rspec"`.
  Nunca rode o rspec sem `RAILS_ENV=test`: ele cairia no banco de desenvolvimento.
- Estilo: `bundle exec rubocop`.
- Olist: `rake olist:conectar[email]`, `rake olist:sync`.

## Fluxo de trabalho
- Uma branch por assunto (`feature/...`), commits pequenos em português, specs junto com o código.
- `db/schema.rb` só entra no commit com a migration correspondente.
- Não fazer push, PR, merge nem deploy sem o dono pedir.
- `config/environments/development.rb` pode ter ajuste local (túnel); não commitar.
