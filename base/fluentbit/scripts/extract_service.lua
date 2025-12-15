-- Lua script to extract service name from pod name or labels
-- This script enriches logs with service_name field for routing to service-specific indices

function extract_service_from_pod(tag, timestamp, record)
    -- List of known services (should match your service names in base/services/)
    local services = {
        "attendance-service",
        "audit-service",
        "compliance-service",
        "employee-service",
        "leave-service",
        "notification-service",
        "user-service"
    }
    
    -- Extract service name from pod name
    -- Kubernetes pod naming patterns:
    -- - Deployment: <deployment>-<replica_set>-<pod_hash>
    -- - StatefulSet: <statefulset>-<ordinal>
    local pod_name = record["pod_name"] or ""
    local service = nil
    
    -- Try to match service name in pod_name
    for _, svc in ipairs(services) do
        if string.find(pod_name, svc, 1, true) then
            service = svc
            break
        end
    end
    
    -- Fallback: Check if service label exists
    if not service and record["service"] then
        service = record["service"]
    end
    
    -- If we found a service, add it to the record
    if service then
        record["service_name"] = service
    else
        -- Default for system components (kube-system, kube-public, etc.)
        local namespace = record["namespace"] or ""
        if namespace == "kube-system" or namespace == "kube-public" or namespace == "kube-node-lease" then
            record["service_name"] = "system"
        else
            record["service_name"] = "unknown"
        end
    end
    
    return 2, timestamp, record
end
