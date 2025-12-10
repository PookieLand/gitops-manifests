This folder contains scaffolding for syncing MySQL credentials from AWS Secrets Manager into the cluster using the External Secrets Operator.

Files:
- `clustersecretstore-aws.yaml` - ClusterSecretStore that configures ExternalSecrets Operator to read from AWS Secrets Manager. It currently references a Kubernetes Secret `aws-credentials` for access keys. In production prefer IRSA (IAM role for service account) instead of static keys.
- `externalsecret-mysql.yaml` - ExternalSecret that pulls the `hrms/mysql` secret from AWS Secrets Manager and creates an in-cluster Secret `mysql-credentials` in the `hrms` namespace.

How to use (recommended):
1. Install the External Secrets Operator in your cluster (see https://external-secrets.io).
2. Prefer configuring AWS access via IRSA / IAM role bound to a ServiceAccount used by the operator.
   - If you can't use IRSA, create a Kubernetes Secret named `aws-credentials` in namespace `hrms` (or cluster-wide) with keys `access-key-id` and `secret-access-key`.
3. Commit these YAMLs to your GitOps repo and let ArgoCD sync them (they contain no plaintext secret values).
4. In AWS Secrets Manager create a secret named `hrms/mysql` with keys `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, `MYSQL_PASSWORD`.
5. After ArgoCD sync, the operator will create a `Secret` named `mysql-credentials` in the `hrms` namespace. Use it in your MySQL StatefulSet via `valueFrom.secretKeyRef`.

Notes and best practices:
- Do NOT store AWS access keys in Git. Use IRSA or KMS-backed SOPS if you must store things in Git.
- Use least-privilege IAM policy for the operator (only allow access to the specific secrets or path prefix needed).
- Prefer per-environment secret names (e.g., `hrms/mysql/prod`) and environment-specific Git branches/values files.
- Test in a staging cluster before deploying to production.

Terraform integration
---------------------

This repo includes Terraform in the `HRMS/terraform` folder that can create the AWS Secrets Manager secret `hrms/mysql` and an IAM user with permissions to read it. If you run that Terraform, it will output the IAM access key id and secret (sensitive). Use those values to create the Kubernetes `aws-credentials` Secret (or better: configure IRSA and avoid static keys).

Example CLI to create `aws-credentials` (from CI or local machine, do NOT commit):

```bash
# replace placeholders with Terraform outputs
kubectl -n hrms create secret generic aws-credentials \
   --from-literal=access-key-id="<ACCESS_KEY_ID>" \
   --from-literal=secret-access-key="<SECRET_ACCESS_KEY>"
```

After the ExternalSecrets Operator reads from AWS Secrets Manager it will create `mysql-credentials` in-cluster; the MySQL StatefulSet and service Deployments in this repo are already patched to use that Secret.
