# Quick Fix Guide - Fluentbit Service-Specific Logging

## TL;DR - What Was Wrong and Fixed

### Problem 1: Script Not Found
```
[error] [filter:lua:lua.3] cannot access script '/fluent-bit/scripts/extract_service.lua'
```
**Fix:** Added ConfigMap to mount script

### Problem 2: Service Variable Missing
```
[warn] [env] variable ${SERVICE} is used but not set
```
**Fix:** Use `${FLUENTBIT_TAG_PART1}` instead

### Problem 3: Rewrite Tag Not Working
**Fix:** Explicit regex for service names

---

## Deploy the Fixed Version

```bash
# 1. Fetch latest PR commits
git fetch origin feature/service-specific-logging
git checkout feature/service-specific-logging

# 2. Deploy to staging
kubectl apply -k overlays/staging

# 3. Wait and verify
kubectl rollout status deployment/fluent-bit -n default
```

---

## Verify It's Working (Run These Commands)

### Step 1: Check ConfigMap
```bash
kubectl get cm fluentbit-lua-scripts -n default
```
Should show: `fluentbit-lua-scripts` exists

### Step 2: Verify Script is Mounted
```bash
POD=$(kubectl get pod -n default -l app=fluent-bit -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n default -- ls -la /fluent-bit/scripts/
```
Should show: `extract_service.lua` exists

### Step 3: Check for Errors
```bash
kubectl logs deployment/fluent-bit -n default | grep -c error
```
Should show: `0` (no errors)

### Step 4: Check Tag Rewriting
```bash
kubectl logs deployment/fluent-bit -n default | grep "service\." | head -3
```
Should show tags like: `service.attendance-service`

### Step 5: Verify OpenSearch Indices
```bash
curl -s http://opensearch-host:9200/_cat/indices | grep logs-staging
```
Should show indices like:
- `logs-staging-attendance-service-2025.12.15`
- `logs-staging-audit-service-2025.12.15`
- `logs-staging-system-2025.12.15`

---

## If Something Still Doesn't Work

### Check Fluentbit Logs
```bash
kubectl logs deployment/fluent-bit -n default -f --tail=50
```
Look for:
- ✅ "[info] [engine] started"
- ❌ "[error]" - any error lines
- ✅ "service." - tag rewriting happening

### Verify Lua Script Syntax
```bash
POD=$(kubectl get pod -n default -l app=fluent-bit -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n default -- /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.conf -T
```
Should show config is valid

### Check Output Plugin Connection
```bash
kubectl logs deployment/fluent-bit -n default | grep -i "opensearch\|output"
```
Should show:
- Connection to OpenSearch successful
- No "Connection refused" errors

---

## Quick Rollback (If Needed)

```bash
# Revert to previous version
git revert HEAD
kubectl apply -k overlays/staging

# Delete ConfigMap
kubectl delete cm fluentbit-lua-scripts -n default

# Verify rollback
kubectl rollout status deployment/fluent-bit -n default
```

---

## Expected Behavior After Fix

| Component | Before | After |
|-----------|--------|-------|
| Lua Script | ❌ Not found | ✅ Mounted via ConfigMap |
| Service Variable | ❌ Undefined | ✅ Uses FLUENTBIT_TAG_PART1 |
| Tag Rewriting | ❌ Failing | ✅ kube.* → service.{name} |
| Indices | ❌ logs-kubernetes-staging | ✅ logs-staging-{service} |
| System Logs | - | ✅ logs-staging-system |

---

## Files Changed

```
base/fluentbit/
├── values-shared.yaml          (UPDATED - fixes)
├── kustomization.yaml          (NEW - ConfigMap)
├── scripts/
│   └── extract_service.lua     (unchanged)
├── SERVICE_LOGGING.md          (documentation)
├── FIXES.md                    (detailed fixes)
└── QUICK_FIX.md               (this file)
```

---

## Need More Help?

1. **Read full explanation:** `base/fluentbit/FIXES.md`
2. **Architecture overview:** `base/fluentbit/SERVICE_LOGGING.md`
3. **Check PR:** https://github.com/PookieLand/gitops-manifests/pull/31

---

## Success Criteria ✅

- [ ] No errors in Fluentbit logs
- [ ] ConfigMap `fluentbit-lua-scripts` exists
- [ ] Lua script mounted at `/fluent-bit/scripts/`
- [ ] Service tags appearing in logs (e.g., `service.attendance-service`)
- [ ] OpenSearch indices created (8 total, one per service + system)
- [ ] Logs appear in correct service-specific indices

Once all boxes checked → **Ready for production deployment! 🚀**
