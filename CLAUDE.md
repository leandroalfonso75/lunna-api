# Lunna API (Rails 8.1, modo API)

Back-end do Lunna, painel para vendedores do Mercado Livre. O front fica em `lunna-web`.

## Leia antes de mexer
- `docs/secoes/README.md`: um documento por item do menu (o que faz, dados, regras, arquivos). Ao mudar uma regra,
  atualize o documento da seção no mesmo commit.
- `docs/DECISOES.md` prevalece sobre `docs/SPEC.md`. `docs/METRICS.md` define as métricas.

## Mapa de pastas
- `app/controllers/`: finos; só autenticam, escopam pela empresa e renderizam.
- `app/services/`: regras de negócio. `painel/` (visão geral, anúncios), `abc/`, `ml/` (leitura do Mercado Livre),
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
- Testes: `docker compose run --rm api bundle exec rspec` (ou `bin/rspec` fora do Docker).
- Estilo: `bundle exec rubocop`.
- Olist: `rake olist:conectar[email]`, `rake olist:sync`.

## Fluxo de trabalho
- Uma branch por assunto (`feature/...`), commits pequenos em português, specs junto com o código.
- `db/schema.rb` só entra no commit com a migration correspondente.
- Não fazer push, PR, merge nem deploy sem o dono pedir.
- `config/environments/development.rb` pode ter ajuste local (túnel); não commitar.
