# syntax=docker/dockerfile:1
# Mesmo formato do timeia-api: `builder` (toolchain + gems de dev/test, usado
# pelo docker-compose e pela suíte) e `runtime` slim para produção.
ARG RUBY_VERSION=3.3.12
FROM ruby:${RUBY_VERSION} AS builder
WORKDIR /app
# Usuário 1000 também no builder: arquivos gerados pelo compose (schema.rb,
# migrations) ficam com o dono do host, e o volume de gems herda a posse.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /usr/local/bundle /app
USER rails:rails
COPY --chown=rails:rails Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3
COPY --chown=rails:rails . .

FROM ruby:${RUBY_VERSION}-slim AS runtime
WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH="/usr/local/bundle"
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
COPY Gemfile Gemfile.lock ./
# Toolchain instalada e removida no MESMO RUN: numa camada separada ela ficaria
# na imagem final mesmo depois do purge.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev curl libpq5 libyaml-0-2 && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf /usr/local/bundle/cache && \
    apt-get purge -y build-essential libpq-dev libyaml-dev && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*
COPY --chown=rails:rails . .
RUN bundle exec bootsnap precompile app/ lib/ && \
    mkdir -p tmp/pids log && chown -R rails:rails tmp log
USER rails:rails
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD curl -f http://localhost:3000/up || exit 1
CMD ["bash", "-lc", "rm -f tmp/pids/server.pid && bundle exec puma -C config/puma.rb"]
