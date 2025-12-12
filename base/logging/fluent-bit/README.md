This folder contains Fluent Bit manifests for shipping Kubernetes logs.

Quick apply (cluster):

```
# preferred: use kustomize (preserves ordering/overlays)
kubectl apply -k base/logging/fluent-bit/
```

Configs:
- `namespace.yaml` - `logging` namespace
- `serviceaccount.yaml`, `clusterrole.yaml`, `clusterrolebinding.yaml` - RBAC
- `configmap.yaml` - Fluent Bit config, parsers, Lua script and output snippets
- `daemonset.yaml` - Fluent Bit DaemonSet
- `kustomization.yaml` - kustomize entry for the folder

Notes
- GitOps / ArgoCD: an Argo Application is provided at `argo/templates/app-logging.yaml` which points to this path. Use that to let Argo manage the Fluent Bit deployment.
- Secrets: this repo contains a plaintext `secret.yaml` example. In this setup we use ExternalSecrets to populate the runtime secret from AWS Secrets Manager: see `base/external-secrets/externalsecrets/{production,staging}/opensearch-fluentbit-externalsecret.yaml`. Do NOT commit real secrets to Git; remove or ignore `secret.yaml` in production.
- Environment tagging: Fluent Bit adds an `environment` field to each record using a small Lua script that derives the value from the Kubernetes namespace (maps `production*` → `production`, `staging*` → `staging`, fallback `unknown`). This lets a single DaemonSet serve multiple namespaces while keeping indices separated.
- OpenSearch output: `configmap.yaml` includes an `opensearch-output.conf` snippet that writes to `kubernetes_logs_${environment}`. Edit that section to change destination (Loki/Elasticsearch) or TLS settings. If OpenSearch uses a self-signed cert, provide a CA bundle or set `tls.verify Off` (not recommended).
- Network & IAM: ensure nodes can reach the OpenSearch EC2 (security groups, routing) and that the ClusterSecretStore/IRSA role has permission to read the Secrets Manager keys referenced by ExternalSecrets.

Validation
- Check Fluent Bit pods: `kubectl -n logging get pods -l app=fluent-bit`
- Tail logs: `kubectl -n logging logs -l app=fluent-bit --tail 100` (look for `environment` field)
- Check indices: `curl -u <user>:<pass> https://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/indices | grep kubernetes_logs`

Replace output plugin config in `configmap.yaml` to send logs to Loki/Elasticsearch/remote endpoint if desired.
