# config/sample — file convention

ArgoCD syncs this directory as a plain **directory source** (`apps/sample.yaml`). ArgoCD loads only
`*.yaml`, `*.yml`, `*.json` (and `.jsonnet`) from a directory source; every other file — this README
and the `*.yaml.tpl` templates — is skipped before include/exclude filtering
(<https://argo-cd.readthedocs.io/en/stable/user-guide/directory/>).

| File | Kind | Why |
|---|---|---|
| `namespace.yaml` | plain | no apply-time values |
| `serviceaccount.yaml` | plain | role ARN is fixed by LAYERS.md |
| `secretstore.yaml`, `externalsecret.yaml` | plain | store name, region, secret name are fixed |
| `web-service.yaml` | plain | |
| `keda-triggerauth.yaml` | plain | |
| `web-deployment.yaml.tpl` | **template** | `__ECR_URL__`, `__IMAGE_TAG__` |
| `consumer-deployment.yaml.tpl` | **template** | `__ECR_URL__`, `__IMAGE_TAG__`, `__SQS_URL__` |
| `web-ingress.yaml.tpl` | **template** | `__CERT_ARN__` |
| `keda-scaledobject.yaml.tpl` | **template** | `__SQS_URL__` |

Templates hold exactly four placeholders: `__CERT_ARN__` `__ECR_URL__` `__IMAGE_TAG__` `__SQS_URL__`.
`scripts/render-gitops.sh` (in the lab root, not this repo) reads them from terragrunt outputs
(`05-dns`: `certificate_arn`; `00-account`: `ecr_repository_url`, `sqs_queue_url`) plus the tag printed
by `scripts/build-push.sh`, writes `<name>.yaml` next to each `<name>.yaml.tpl`, and the rendered files
are committed. Until that commit exists ArgoCD sees only the plain files, which is harmless: the
Deployments, Ingress and ScaledObject simply are not there yet.

Edit the `.tpl`, re-render, commit both. Never hand-edit a rendered `.yaml`.
