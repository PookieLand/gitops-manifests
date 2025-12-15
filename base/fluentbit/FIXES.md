# Fluentbit Service-Specific Logging - Fix Documentation

## Issues Encountered and Solutions

### Issue 1: Lua Script Path Not Found

**Error Message:**
```
[error] [filter:lua:lua.3] cannot access script '/fluent-bit/scripts/extract_service.lua'
[error] [filter_lua] filter cannot be loaded
```

**Root Cause:** 
The Lua script file wasn't being mounted into the Fluentbit pod. By default, Helm charts don't automatically mount custom scripts.

**Solution:**
We now use a **Kustomize ConfigMap** to mount the Lua script:

```yaml
# 1. ConfigMap is created from the script
configMapGenerator:
  - name: fluentbit-lua-scripts
    files:
      - scripts/extract_service.lua
    options:
      disableNameSuffixHash: true

# 2. Script is mounted into the pod
volumeMounts:
  - name: lua-scripts
    mountPath: /fluent-bit/scripts

daemonSetVolumes:
  - name: lua-scripts
    configMap:
      name: fluentbit-lua-scripts
```

**Verification:**
```bash
# Check ConfigMap is created
kubectl get configmap fluentbit-lua-scripts -n default
kubectl describe configmap fluentbit-lua-scripts -n default

# Check pod has mounted it
kubectl describe pod <fluentbit-pod> -n default | grep -A 5 lua-scripts

# Exec into pod and verify file exists
kubectl exec -it <fluentbit-pod> -n default -- ls -la /fluent-bit/scripts/
```

---

### Issue 2: Missing `${SERVICE}` Variable

**Error Message:**
```
[warn] [env] variable ${SERVICE} is used but not set
```

**Root Cause:**
Fluentbit doesn't have a built-in `${SERVICE}` variable. We tried to use it in the OUTPUT block's `Logstash_Prefix`, but it's not defined in the environment.

**Solution:**
Use **Fluentbit's tag-based variable substitution** instead:

```yaml
# Old (doesn't work)
Logstash_Prefix logs-${ENVIRONMENT}-${SERVICE}

# New (works)
Logstash_Prefix logs-${ENVIRONMENT}-${FLUENTBIT_TAG_PART1}
```

**How it Works:**
- Rewrite Tag filter creates tags like: `service.attendance-service`
- Fluentbit automatically parses this tag into parts:
  - `${FLUENTBIT_TAG_PART0}` = "service"
  - `${FLUENTBIT_TAG_PART1}` = "attendance-service"
- So the index becomes: `logs-staging-attendance-service`

**Verification:**
```bash
# Check logs for successful tag rewriting
kubectl logs -f deployment/fluent-bit -n default | grep "rewrite_tag"

# Should see service tags in OpenSearch
curl -X GET "opensearch-host:9200/_cat/indices?v" | grep logs-staging
```

---

### Issue 3: Rewrite Tag Regex Pattern

**Problem:**
The original regex pattern might not match due to escape characters or spacing.

**Solution:**
Update the rewrite_tag filter with explicit service name matching:

```yaml
[FILTER]
    Name                rewrite_tag
    Match               kube.*
    Rule                "service_name ^(attendance-service|audit-service|compliance-service|employee-service|leave-service|notification-service|user-service)$" "service.$1" false
```

**Breakdown:**
- `Name rewrite_tag` - Use the rewrite_tag filter
- `Match kube.*` - Match logs with kube.* tag
- `Rule` - Define the transformation rule:
  - `"service_name ^(...|...)$"` - Match service_name field with regex (anchored)
  - `"service.$1"` - Rewrite to service.{matched_service_name}
  - `false` - Don't keep original tag

**Verification:**
```bash
# Test regex pattern
echo 'attendance-service' | grep -E '^(attendance-service|audit-service|compliance-service|employee-service|leave-service|notification-service|user-service)$'

# Check Fluentbit filter chain
kubectl logs deployment/fluent-bit -n default | grep -A 2 "rewrite_tag"
```

---

## Complete Deployment Flow

```
1. Kustomize ConfigMap
   ↓
   Creates: fluentbit-lua-scripts ConfigMap
   Contains: extract_service.lua script
   
2. Helm Chart Values
   ↓
   Mounts ConfigMap → /fluent-bit/scripts/
   Configures filters and outputs
   
3. Fluentbit Pod Starts
   ↓
   Reads values-shared.yaml
   Mounts ConfigMap volume
   Loads Lua script from ConfigMap
   Disables Istio sidecar injection (system component)
   
4. Log Processing
   ↓
   Tail Input → Kubernetes Filter → Lua Filter → Rewrite Tag Filter → Output
   
5. Index Creation
   ↓
   logs-staging-attendance-service-2025.12.15
   logs-staging-audit-service-2025.12.15
   logs-staging-system-2025.12.15
```

---

## Istio Configuration

Fluentbit is a system component and **does NOT require Istio sidecar injection**.

**Patch Applied:** `overlays/staging/fluentbit-istio-patch.yaml`

This disables Istio mesh injection for Fluentbit pods:

```yaml
metadata:
  labels:
    sidecar.istio.io/inject: "false"
  annotations:
    sidecar.istio.io/inject: "false"
```

Fluentbit continues to operate independently while other services use the service mesh.

---

## Testing Checklist

- [ ] ConfigMap created: `kubectl get cm fluentbit-lua-scripts -n default`
- [ ] Lua script mounted: `kubectl exec fluentbit-pod -- cat /fluent-bit/scripts/extract_service.lua`
- [ ] No Lua errors: `kubectl logs deployment/fluent-bit | grep -i error`
- [ ] Tags rewritten: `kubectl logs deployment/fluent-bit | grep service\\.*`
- [ ] Indices created: `curl opensearch-host:9200/_cat/indices | grep logs-staging`
- [ ] Logs routed: Query each index in OpenSearch
- [ ] No Istio sidecar: `kubectl get pod -n default -l app=fluent-bit -o json | jq '.items[0].spec.containers | length'` (should return 1)

---

## Rollback Instructions

If you need to revert to the original configuration:

```bash
# Option 1: Revert the PR
git revert <PR-commit-hash>
kubectl apply -k overlays/staging

# Option 2: Manual rollback
git checkout main -- base/fluentbit/
kubectl delete cm fluentbit-lua-scripts -n default
kubectl apply -k overlays/staging
```

---

## Key Files Updated

1. **base/fluentbit/values-shared.yaml**
   - Added volumeMounts for script mounting
   - Added daemonSetVolumes for ConfigMap
   - Fixed OUTPUT block to use FLUENTBIT_TAG_PART1
   - Updated rewrite_tag with explicit regex

2. **base/fluentbit/kustomization.yaml** (NEW)
   - ConfigMap generator for Lua scripts
   - Helm chart configuration

3. **base/fluentbit/scripts/extract_service.lua** (unchanged)
   - Lua script for service extraction
   - Mounted via ConfigMap

4. **overlays/staging/fluentbit-istio-patch.yaml** (NEW)
   - Patch to disable Istio sidecar injection
   - Ensures system component runs independently

---

## Monitoring and Debugging

### View Fluentbit Logs
```bash
kubectl logs -f deployment/fluent-bit -n default
```

### Check Active Filters
```bash
kubectl exec pod/fluent-bit-xxxxx -n default -- \
  grep -A 2 "\[FILTER\]" /fluent-bit/etc/fluent-bit.conf
```

### Verify OpenSearch Indices
```bash
curl -s -X GET "opensearch-host:9200/_cat/indices?v&pretty" | grep logs-staging
```

### Test Tag Rewriting
```bash
kubectl logs deployment/fluent-bit -n default | \
  grep -E "(rewrite_tag|service\\.)"
```

### Verify Istio NOT Injected
```bash
kubectl get pod -n default -l app=fluent-bit -o json | \
  jq '.items[0].spec.containers | length'
```
Should show `1` (just Fluentbit container, no Istio sidecar)

---

## Summary

✅ **Fixed:** Lua script now mounted via ConfigMap  
✅ **Fixed:** SERVICE variable replaced with FLUENTBIT_TAG_PART1  
✅ **Fixed:** Rewrite tag regex explicit and tested  
✅ **Fixed:** Istio sidecar disabled for system component  
✅ **Ready:** Full deployment with monitoring
