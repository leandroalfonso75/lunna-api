# cd/prod — deploy do Lunna em produção (Kubernetes)

Mesmo padrão do timeia/pipefill: ingress-nginx, cert-manager com o ClusterIssuer
`letsencrypt-prod`, storage `local-path` e manifests planos aplicados com `kubectl apply`.

| Item | Produção |
|---|---|
| Servidor | `root@179.197.225.138`, k3s single-node |
| Front | https://gestao.lunnashop.com.br |
| API | https://api.lunnashop.com.br (saúde em `/up`) |
| Namespace | `lunna` |
| Segredos | `~/.lunna_prod_secrets.env` na máquina de quem faz o deploy (0600) |

| Recurso | Arquivo | Repo |
|---|---|---|
| Namespace `lunna` | `namespace.yml` (idêntico nos dois repos) | lunna-api / lunna-web |
| Emissor de certificados | `cluster-issuer.yml` (uma vez por cluster) | lunna-api |
| Postgres 16 (StatefulSet, 20Gi `local-path`) | `postgres-statefulset.yml`, `postgres-service.yml` | lunna-api |
| Backup diário (`pg_dump`, 30 dias) | `cronjob-backup.yml` | lunna-api |
| Migrações (um Job por versão) | `job-migrate.yml` | lunna-api |
| API (Puma, 2 réplicas) | `deployment.yml`, `service.yml`, `ingress.yml` | lunna-api |
| Worker Solid Queue (sync a cada 5 min) | `deployment-jobs.yml` | lunna-api |
| Front Nuxt | `lunna-web/cd/prod/*.yml` | lunna-web |

## Deploy

Da raiz do lunna-api, com o lunna-web ao lado (`../lunna-web`), Docker local e acesso SSH
por chave ao servidor:

```bash
VERSION=0.1.1 ./cd/prod/deploy.sh
```

O [`deploy.sh`](deploy.sh) builda as duas imagens nesta máquina e importa no containerd do
servidor, sem registry. Depois aplica Secret, Postgres, ConfigMap e o Job de migração, e
espera o Job terminar antes de trocar API, worker e front. Por fim aplica Ingress e backup.
Use uma `VERSION` nova a cada release: ela vira a tag das imagens e o nome do Job.

Para outro servidor ou domínio: `SSH=… API_HOST=… APP_HOST=… WEB_DIR=…` (o script troca os
domínios dos manifests na hora de aplicar).

Os manifests mantêm `imagePullSecrets: dockerhub` e `imagePullPolicy: IfNotPresent`: com a
imagem importada no nó, o k8s não puxa nada. Para voltar ao Docker Hub, faça `docker push`
das imagens e crie o Secret `dockerhub` no namespace.

### Segredos

Na primeira execução o script gera `~/.lunna_prod_secrets.env` (senha do banco,
`SECRET_KEY_BASE`, `ACTIVE_RECORD_ENCRYPTION_*`) e o aplica como Secret `lunna-api-secrets`.
**Guarde esse arquivo num cofre.** As chaves `ACTIVE_RECORD_ENCRYPTION_*` criptografam os
tokens do Mercado Livre e as chaves da OpenRouter no banco; perdê-las obriga todas as
empresas a reconectar.

Para ligar a conexão com o Mercado Livre, preencha `ML_CLIENT_ID` e `ML_CLIENT_SECRET` nesse
arquivo e rode o deploy de novo. No DevCenter, a Redirect URI é
`https://api.lunnashop.com.br/auth/ml/callback`, com permissões de leitura e escrita e
`offline_access`.

## Servidor novo (feito uma vez em 2026-09-25)

```bash
# k3s estável sem o Traefik (o padrão aqui é ingress-nginx)
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable \
  INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 600" sh -

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.2/cert-manager.yaml
kubectl apply -f cd/prod/cluster-issuer.yml   # depois que o cert-manager estiver no ar
```

- O k3s já traz o provisionador `local-path` (StorageClass padrão) e um load balancer que
  publica o ingress-nginx nas portas 80 e 443 do servidor.
- As portas 6443 (API do Kubernetes) e 10250 (kubelet) ficam bloqueadas na interface pública
  pelo serviço systemd `k3s-public-lockdown` (regras iptables e ip6tables em `eth0`). O acesso
  ao cluster é por SSH e `kubectl` no próprio servidor.
- DNS: `gestao` e `api` em `lunnashop.com.br` apontam direto para o IP, o que permite a
  validação HTTP do Let's Encrypt.

## Operação

```bash
ssh root@179.197.225.138
kubectl -n lunna get pods,ingress,certificate
kubectl -n lunna logs deploy/lunna-api -f          # ou deploy/lunna-jobs
kubectl -n lunna exec -it deploy/lunna-api -- bin/rails console
kubectl -n lunna create job --from=cronjob/lunna-postgres-backup backup-manual
```

- Rodadas de sincronização por conta: tela Configurações › Contas (`GET /api/sync/runs`).
- Job de migração com falha: o script mostra o log e para antes de trocar API, worker e front.
  Corrija, gere nova versão e rode de novo.
