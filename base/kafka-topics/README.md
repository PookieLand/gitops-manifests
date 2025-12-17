# Kafka Topics via Strimzi (GitOps)

Recommended: manage topics declaratively using `KafkaTopic` CRs. The Topic Operator reconciles these into Kafka automatically.

Where to add topics
- Base: put shared topics in `base/kafka-topics/base/topics/`.
- Env-specific: add patches or env-only topics in overlays:
  - `base/kafka-topics/overlays/staging/`
  - `base/kafka-topics/overlays/production/`

Minimal topic example
```yaml
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: example-topic
  labels:
    strimzi.io/cluster: kafka  # must match Kafka.metadata.name
spec:
  partitions: 3
  replicas: 1                   # single-broker cluster
  config:
    retention.ms: 604800000
```

Notes
- Label `strimzi.io/cluster` must equal your Kafka CR name (`kafka` in this repo).
- With single broker, use `replicas: 1` and accept no-HA tradeoffs.
- We disable `auto.create.topics` at the broker; create all topics via CRs.

Argo sync order
- Operator (wave 0) → Kafka (wave 1) → Topics (wave 2). SSA enabled to avoid field conflicts.

Optional: job-based creation (not recommended)
If you must mimic the old Helm hook, you can add an ArgoCD PostSync Job. Example template (adjust topic list as needed):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: create-topics
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: kafka-topics
          image: quay.io/strimzi/kafka:0.49.1-kafka-4.1.1
          command:
            - /bin/bash
            - -lc
            - |
              set -euo pipefail
              KAFKA_BOOTSTRAP="kafka-kafka-bootstrap:9092" # <cluster>-kafka-bootstrap:9092
              bin/kafka-topics.sh --bootstrap-server "$KAFKA_BOOTSTRAP" --create --if-not-exists --topic example-topic --partitions 3 --replication-factor 1
```

Prefer CRs: they are idempotent, reviewable, and aligned with GitOps.
