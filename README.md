# eks-lab-gitops

GitOps source for the `eks-lab` EKS cluster (us-west-2, account 859741818496). ArgoCD is installed by
Terraform/Terragrunt (`eks-lab-infra` layer `30-argocd`) together with a single **root Application**
pointing at `apps/` on `main`. Everything else in the cluster is owned by ArgoCD from this repo.

## What ArgoCD owns

```
apps/                      app-of-apps children (root Application -> these three)
  keda.yaml                Helm chart kedacore/keda 2.21.0            -> ns keda           (wave 0)
  external-secrets.yaml    Helm chart external-secrets 2.14.0          -> ns external-secrets (wave 0)
  sample.yaml              directory config/sample                     -> ns sample         (wave 1)
config/sample/             the workload: web (gunicorn) + consumer (SQS dials) + their KEDA/ESO glue
```

Not owned here (Terraform's): the EKS cluster, node group, VPC, IRSA roles, the AWS Load Balancer
Controller, ArgoCD itself, and the root Application.

## Sync waves

| Wave | Application | Reason |
|---|---|---|
| 0 | `keda`, `external-secrets` | install the CRDs (`ScaledObject`, `TriggerAuthentication`, `ClusterSecretStore`, `ExternalSecret`) and the controllers with their IRSA-annotated ServiceAccounts |
| 1 | `sample` | uses those CRDs |

In an app-of-apps, waves order the *Application objects*, not the completion of the child syncs
(ArgoCD does not evaluate child-Application health by default since 1.8). So `sample` carries
`SkipDryRunOnMissingResource=true`: without it the very first sync fails its dry run with
`the server could not find the requested resource` while the wave-0 charts are still installing the
CRDs. With it ArgoCD applies the CRs as soon as the CRDs exist, and a retry policy covers the gap.
Both Helm apps use `ServerSideApply=true` because the ESO and KEDA CRDs are larger than the 256 KiB
`last-applied-configuration` annotation limit.

## KEDA vs ArgoCD on the consumer's replica count

`consumer-deployment.yaml.tpl` sets **no** `spec.replicas`. KEDA's `ScaledObject` owns it
(`minReplicaCount: 0`, `maxReplicaCount: 10`). `apps/sample.yaml` lists `/spec/replicas` of
`Deployment/consumer` under `ignoreDifferences` and enables `RespectIgnoreDifferences=true`, so
`selfHeal` never resets what KEDA set. Setting `replicas: 0` in git instead would make ArgoCD scale
the consumer back to 0 every time KEDA scaled it up.

## Templates and placeholders (`*.yaml.tpl`)

Four values exist only after `terragrunt apply`: `__CERT_ARN__` (ACM), `__ECR_URL__`, `__SQS_URL__`,
and the image tag `__IMAGE_TAG__` (git short SHA from `scripts/build-push.sh`). Files that need them are
committed as `*.yaml.tpl`; `scripts/render-gitops.sh` in the lab root renders them to `*.yaml`, which
are then committed too. ArgoCD's directory source only loads `*.yaml|*.yml|*.json` (plus `.jsonnet`),
so the `.tpl` files and READMEs are ignored automatically — no `include`/`exclude` needed. Details in
`config/sample/README.md`.

## Why this repo is public

It holds **no secrets by design**:

- the only secret value (`eks-lab/sample`) lives in AWS Secrets Manager and is pulled at runtime by
  External Secrets Operator into the k8s Secret `sample-secret`; git only holds the *reference*;
- credentials to AWS are IAM roles bound to ServiceAccounts (IRSA) — ARNs are not secrets;
- the ACM certificate ARN, ECR URL and SQS URL are identifiers, not credentials.

Being public also means ArgoCD needs no repository credential to clone it.

## Versions pinned (2026-11-08)

| Component | Version | Checked with |
|---|---|---|
| KEDA chart / app | 2.21.0 / 2.21.0 | `helm search repo kedacore/keda --versions`; values path `serviceAccount.operator.annotations` from the pulled chart |
| ESO chart / app | 2.14.0 / v2.14.0 | `helm search repo external-secrets/external-secrets --versions`; `installCRDs`, `serviceAccount.{name,annotations}` from the pulled chart |
| KEDA API | `keda.sh/v1alpha1` | chart `templates/crds/` |
| ESO API | `external-secrets.io/v1` | chart CRDs: v1 served+storage; v1beta1 off (`crds.unsafeServeV1Beta1: false`), removal announced 2026-05-01 |
| ALB ssl-policy | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` | AWS "Security policies for your ALB" — current recommendation |
| ALB HSTS attribute | `routing.http.response.strict_transport_security.header_value` | ELBv2 API `ListenerAttribute`; set via `alb.ingress.kubernetes.io/listener-attributes.HTTPS-443` (optional, see the Ingress) |
