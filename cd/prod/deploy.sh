#!/usr/bin/env bash
# Deploy do Lunna (API + front) num servidor k3s via SSH, sem registry:
# builda as imagens nesta máquina, importa no containerd do servidor e aplica
# os manifests de cd/prod trocando domínios (quando diferentes) e a versão.
#
#   VERSION=0.1.1 ./cd/prod/deploy.sh
#
# Padrões: servidor root@179.197.225.138, API api.lunnashop.com.br, front
# gestao.lunnashop.com.br e o lunna-web ao lado deste repo (../lunna-web).
# Para outro ambiente: SSH=... API_HOST=... APP_HOST=... WEB_DIR=... VERSION=...
#
# Na primeira vez gera os segredos em ~/.lunna_prod_secrets.env (0600). Guarde esse
# arquivo num cofre: as chaves ACTIVE_RECORD_ENCRYPTION_* protegem os tokens do
# Mercado Livre e as chaves da OpenRouter; perdê-las obriga todas as empresas a
# reconectar. Para configurar o app do Mercado Livre, preencha ML_CLIENT_ID e
# ML_CLIENT_SECRET nesse arquivo e rode o deploy de novo.
set -euo pipefail

SSH="${SSH:-root@179.197.225.138}"
API_HOST="${API_HOST:-api.lunnashop.com.br}"
APP_HOST="${APP_HOST:-gestao.lunnashop.com.br}"
VERSION="${VERSION:-0.1.0}"
API_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WEB_DIR="${WEB_DIR:-$API_DIR/../lunna-web}"
SECRETS_FILE="${SECRETS_FILE:-$HOME/.lunna_prod_secrets.env}"
JOB="lunna-api-migrate-${VERSION//./-}"

remote() { ssh -o BatchMode=yes "$SSH" "$@"; }

# Troca domínios e versão; vários arquivos viram um só documento YAML.
render() {
  for file in "$@"; do
    sed -e "s/api\.lunnashop\.com\.br/$API_HOST/g" \
        -e "s/gestao\.lunnashop\.com\.br/$APP_HOST/g" \
        -e "s/lunna-api:0\.1\.0/lunna-api:$VERSION/g" \
        -e "s/lunna-web:0\.1\.0/lunna-web:$VERSION/g" \
        -e "s/lunna-api-migrate-0-1-0/$JOB/g" "$file"
    echo "---"
  done
}
apply() { render "$@" | remote kubectl apply -f -; }

echo "==> Imagens $VERSION (build local + import no k3s)"
docker build --network host -q -t "vinnialfonso/lunna-api:$VERSION" "$API_DIR" >/dev/null
docker build --network host -q -t "vinnialfonso/lunna-web:$VERSION" "$WEB_DIR" >/dev/null
for image in lunna-api lunna-web; do
  docker save "vinnialfonso/$image:$VERSION" | gzip | remote "gunzip | k3s ctr -n k8s.io images import - >/dev/null"
done

echo "==> Segredos"
if [ ! -f "$SECRETS_FILE" ]; then
  umask 077
  db_password="$(openssl rand -hex 24)"
  cat > "$SECRETS_FILE" <<SECRETS
DATABASE_PASSWORD=$db_password
DATABASE_URL=postgres://lunna_api:$db_password@lunna-postgres:5432/lunna_api_production
SECRET_KEY_BASE=$(openssl rand -hex 64)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -base64 32)
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -base64 32)
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -base64 32)
ML_CLIENT_ID=
ML_CLIENT_SECRET=
SECRETS
  echo "    gerados em $SECRETS_FILE (guarde num cofre)"
fi
apply "$API_DIR/cd/prod/namespace.yml"
remote "kubectl -n lunna create secret generic lunna-api-secrets --from-env-file=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -" < "$SECRETS_FILE"

echo "==> Postgres"
apply "$API_DIR/cd/prod/postgres-statefulset.yml" "$API_DIR/cd/prod/postgres-service.yml"
remote "kubectl -n lunna rollout status statefulset/lunna-postgres --timeout=300s"

echo "==> Migrações ($JOB)"
apply "$API_DIR/cd/prod/configmap.yml"
remote "kubectl -n lunna delete job $JOB --ignore-not-found"
apply "$API_DIR/cd/prod/job-migrate.yml"
if ! remote "kubectl -n lunna wait --for=condition=complete --timeout=300s job/$JOB"; then
  remote "kubectl -n lunna logs job/$JOB --tail=50" || true
  exit 1
fi

echo "==> API e worker"
apply "$API_DIR/cd/prod/service.yml" "$API_DIR/cd/prod/deployment.yml" "$API_DIR/cd/prod/deployment-jobs.yml"
remote "kubectl -n lunna rollout restart deployment/lunna-api deployment/lunna-jobs"
remote "kubectl -n lunna rollout status deployment/lunna-api --timeout=300s && kubectl -n lunna rollout status deployment/lunna-jobs --timeout=300s"
apply "$API_DIR/cd/prod/ingress.yml" "$API_DIR/cd/prod/cronjob-backup.yml"

echo "==> Front"
apply "$WEB_DIR/cd/prod/configmap.yml" "$WEB_DIR/cd/prod/service.yml" "$WEB_DIR/cd/prod/deployment.yml"
remote "kubectl -n lunna rollout restart deployment/lunna-web && kubectl -n lunna rollout status deployment/lunna-web --timeout=300s"
apply "$WEB_DIR/cd/prod/ingress.yml"

echo "==> Pronto"
remote "kubectl -n lunna get pods,ingress,certificate"
echo "    https://$APP_HOST  (API: https://$API_HOST/up)"
