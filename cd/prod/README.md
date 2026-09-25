# cd/prod — deploy do Lunna em produção (Kubernetes)

Mesmo padrão do timeia/pipefill: ingress-nginx + cert-manager (`ClusterIssuer letsencrypt-prod`),
imagens privadas no Docker Hub (`vinnialfonso/*`), manifests planos aplicados com `kubectl apply`.
Tudo roda no namespace `lunna`:

| Recurso | Arquivo | Repo |
|---|---|---|
| Namespace `lunna` | `namespace.yml` (idêntico nos dois repos) | lunna-api / lunna-web |
| Postgres 16 (StatefulSet, 20Gi `local-path`) | `postgres-statefulset.yml`, `postgres-service.yml` | lunna-api |
| Backup diário (`pg_dump`, 30 dias) | `cronjob-backup.yml` | lunna-api |
| Migrações (um Job por release) | `job-migrate.yml` | lunna-api |
| API (Puma, 2 réplicas) | `deployment.yml`, `service.yml`, `ingress.yml` | lunna-api |
| Worker Solid Queue (sync a cada 5 min) | `deployment-jobs.yml` | lunna-api |
| Front Nuxt | `lunna-web/cd/prod/*.yml` | lunna-web |

## 1. Antes do primeiro deploy

1. **Domínios.** Os manifests usam placeholders `api.change-me.invalid` e `app.change-me.invalid`.
   Troque nos dois repos e aponte o DNS (Cloudflare) para o IP do cluster:
   ```bash
   API=api.seudominio.com.br APP=app.seudominio.com.br
   sed -i "s/api\.change-me\.invalid/$API/g; s/app\.change-me\.invalid/$APP/g" \
     ~/workspace/lunna/lunna-api/cd/prod/*.yml ~/workspace/lunna/lunna-web/cd/prod/*.yml
   ```
2. **App do Mercado Livre** (DevCenter): Redirect URI `https://<API>/auth/ml/callback`,
   permissões de leitura e escrita + `offline_access`. Anote Client ID e Secret.
3. **Secret da API**: copie o modelo e preencha (o `secrets.yml` é gitignored):
   ```bash
   cp cd/prod/secrets.example.yml cd/prod/secrets.yml
   openssl rand -hex 64      # SECRET_KEY_BASE
   openssl rand -base64 32   # cada ACTIVE_RECORD_ENCRYPTION_* (três valores diferentes)
   openssl rand -hex 24      # DATABASE_PASSWORD (repita no DATABASE_URL)
   ```
   As chaves `ACTIVE_RECORD_ENCRYPTION_*` criptografam os tokens do Mercado Livre no banco:
   perdê-las obriga todas as empresas a reconectar as contas. Guarde num cofre.
4. **Pull secret do Docker Hub** (repos privados), uma vez:
   ```bash
   kubectl apply -f cd/prod/namespace.yml
   kubectl -n lunna create secret docker-registry dockerhub \
     --docker-username=vinnialfonso --docker-password='<token de acesso do Docker Hub>'
   ```

## 2. Build e push das imagens

Versão semver igual nos dois repos (ex.: `0.1.0`). Atualize a tag em `deployment.yml`,
`deployment-jobs.yml` e `job-migrate.yml` (imagem **e** nome do Job) antes de aplicar.

```bash
cd ~/workspace/lunna/lunna-api && docker build -t vinnialfonso/lunna-api:0.1.0 . && docker push vinnialfonso/lunna-api:0.1.0
cd ~/workspace/lunna/lunna-web && docker build -t vinnialfonso/lunna-web:0.1.0 . && docker push vinnialfonso/lunna-web:0.1.0
```

## 3. Aplicar (ordem importa)

```bash
cd ~/workspace/lunna/lunna-api
kubectl apply -f cd/prod/namespace.yml
kubectl apply -f cd/prod/secrets.yml                     # o real, não o .example
kubectl apply -f cd/prod/postgres-statefulset.yml -f cd/prod/postgres-service.yml
kubectl -n lunna rollout status statefulset/lunna-postgres
kubectl apply -f cd/prod/configmap.yml

# Migrações: o Job termina antes de web/jobs subirem com a imagem nova.
kubectl apply -f cd/prod/job-migrate.yml
kubectl -n lunna wait --for=condition=complete --timeout=300s job/lunna-api-migrate-0-1-0

kubectl apply -f cd/prod/service.yml -f cd/prod/deployment.yml -f cd/prod/deployment-jobs.yml
kubectl -n lunna rollout restart deployment/lunna-api deployment/lunna-jobs   # pega Secret/ConfigMap novos
kubectl -n lunna rollout status deployment/lunna-api
kubectl apply -f cd/prod/ingress.yml -f cd/prod/cronjob-backup.yml

cd ~/workspace/lunna/lunna-web
kubectl apply -f cd/prod/configmap.yml -f cd/prod/service.yml -f cd/prod/deployment.yml -f cd/prod/ingress.yml
kubectl -n lunna rollout status deployment/lunna-web

kubectl -n lunna get certificate      # TLS emitido pelo cert-manager
```

Job de migração com falha: `kubectl -n lunna logs job/lunna-api-migrate-0-1-0`. Nada de web/jobs
novos sobe até ele completar; corrija, gere nova imagem e aplique de novo.

## 4. Operação

- Logs: `kubectl -n lunna logs deploy/lunna-api -f` / `deploy/lunna-jobs -f`.
- Rodadas de sincronização por conta: `GET /api/sync/runs?account_id=…` (tela Configurações › Contas).
- Backup manual: `kubectl -n lunna create job --from=cronjob/lunna-postgres-backup backup-manual`.
- Console: `kubectl -n lunna exec -it deploy/lunna-api -- bin/rails console`.
