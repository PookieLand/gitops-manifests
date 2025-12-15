# Service-Specific Logging Configuration

## Overview

This document describes the enhanced Fluentbit configuration that routes logs to service-specific indices in OpenSearch, making it easier to filter and analyze logs by service in the OpenSearch Explorer UI.

## What Changed

### Before
All logs were sent to a single index prefix:
- `logs-kubernetes-staging`
- `logs-kubernetes-production`

This made it difficult to filter logs by individual services.

### After
Logs are now routed to service-specific indices:
- `logs-staging-attendance-service`
- `logs-staging-audit-service`
- `logs-staging-compliance-service`
- `logs-staging-employee-service`
- `logs-staging-leave-service`
- `logs-staging-notification-service`
- `logs-staging-user-service`
- `logs-staging-system` (for system components)

## How It Works

### 1. Service Extraction (Lua Script)

The `extract_service.lua` script analyzes each log's pod name and extracts the service name:

```lua
-- Matches pod names like: attendance-service-7f8d9c5b8-abc12
-- Extracts: attendance-service
```

**Supported services** (from `base/services/`):
- attendance-service
- audit-service
- compliance-service
- employee-service
- leave-service
- notification-service
- user-service

### 2. Tag Rewriting

The `rewrite_tag` filter transforms log tags based on service name:

```
kube.var.log.containers.attendance-service-7f8d9c5b8-abc12_default_xxx.log
    ↓
service.attendance-service
```

### 3. Routing to OpenSearch

Two OUTPUT blocks route logs:

**Service-specific output** (matches `service.*`):
- Uses `Logstash_Prefix logs-${ENVIRONMENT}-${SERVICE}`
- Creates indices like: `logs-staging-attendance-service-2025.12.15`

**Fallback output** (matches remaining `kube.*` tags):
- Routes system logs to: `logs-staging-system-2025.12.15`

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│            Kubernetes Containers                        │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Attendance   │  │    Audit     │  │  Employee    │  │
│  │   Service    │  │   Service    │  │   Service    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
                          ↓
                    Tail Plugin
                  /var/log/containers
                          ↓
┌─────────────────────────────────────────────────────────┐
│              Fluentbit Filters                          │
│  1. Kubernetes - enrich with metadata                   │
│  2. Lua - extract service_name                          │
│  3. Rewrite Tag - tag as service.{service_name}         │
└─────────────────────────────────────────────────────────┘
                          ↓
        ┌─────────────────┴─────────────────┐
        ↓                                   ↓
   service.*                            kube.*
   OUTPUT blocks                     (fallback)
        ↓                                   ↓
┌──────────────────────────┐  ┌──────────────────────────┐
│ logs-staging-            │  │ logs-staging-system      │
│   attendance-service     │  │                          │
│   audit-service          │  │ (system components)      │
│   employee-service       │  │                          │
│   etc.                   │  │                          │
└──────────────────────────┘  └──────────────────────────┘
        ↓                                   ↓
            OpenSearch Cluster
```

## Configuration Files

### 1. `values-shared.yaml`
Main Fluentbit Helm values with:
- Enhanced filters (Lua + rewrite_tag)
- Dual OUTPUT blocks (service-specific + fallback)

### 2. `scripts/extract_service.lua`
Lua script that:
- Extracts service name from pod naming patterns
- Handles Deployment and StatefulSet patterns
- Falls back to labels if pod pattern doesn't match
- Marks unknown/system logs as "system"

## Testing the Configuration

### 1. Verify Pod Logs Are Being Generated
```bash
kubectl logs -n default deployment/attendance-service -f
```

### 2. Check Fluentbit Pod
```bash
kubectl get pods -n default -l app=fluent-bit
kubectl logs -n default pod/fluent-bit-xxxxx -f
```

### 3. Query OpenSearch
In OpenSearch Dashboard or Explorer:

```
Index: logs-staging-attendance-service*
Filter: @timestamp > now-1h
```

### 4. Verify Index Creation
```bash
curl -X GET "opensearch-host:9200/_cat/indices?v" | grep logs-staging
```

## Troubleshooting

### Issue: All logs still go to system index

**Cause**: Service name not being extracted

**Solution**:
1. Check Fluentbit logs: `kubectl logs -n default pod/fluent-bit-xxxxx`
2. Verify pod names contain service names
3. Check Lua script syntax in values-shared.yaml

### Issue: Service indices not created

**Cause**: Rewrite_tag filter not matching

**Solution**:
1. Verify rewrite_tag rule regex
2. Check service_name field exists in records
3. Look at OpenSearch index templates

### Issue: High cardinality indices

**Cause**: Too many unique service values

**Solution**:
1. Review Lua script service list
2. Check for typos in service names
3. Consider using OpenSearch index lifecycle policies

## Adding New Services

When adding a new service to `base/services/`:

1. **Add service name to Lua script** (`base/fluentbit/scripts/extract_service.lua`):
   ```lua
   local services = {
       -- existing services...
       "your-new-service"
   }
   ```

2. **Optional: Create service-specific dashboards** in OpenSearch with:
   ```
   Index Pattern: logs-*-your-new-service*
   ```

3. **Deploy** the updated Fluentbit configuration

## Performance Considerations

- **Lua Processing**: Minimal overhead (~1-2ms per log entry)
- **Index Count**: One per service + system = ~8 indices total
- **Query Performance**: Faster searches due to smaller, focused indices
- **Retention Policies**: Can apply per-service retention

## Future Enhancements

- [ ] Add service version tracking
- [ ] Add environment labels (dev/stage/prod)
- [ ] Implement log sampling for high-volume services
- [ ] Create automated service dashboards
- [ ] Add cost tracking per service

## References

- [Fluentbit Documentation](https://docs.fluentbit.io/)
- [Fluentbit Lua Filter](https://docs.fluentbit.io/manual/pipeline/filters/lua)
- [Fluentbit Rewrite Tag](https://docs.fluentbit.io/manual/pipeline/filters/rewrite-tag)
- [OpenSearch Logstash Format](https://opensearch.org/)
