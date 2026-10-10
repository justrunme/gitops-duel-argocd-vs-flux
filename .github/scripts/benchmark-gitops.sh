#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${1:-default}
APP_NAME=${2:-nginx-app}
GITOPS_TOOL=${3:-argocd}

echo "=== GitOps Performance Benchmark: ${GITOPS_TOOL} ==="
echo "Namespace: ${NAMESPACE}"
echo "Application: ${APP_NAME}"
echo ""

measure_time_to_ready() {
    local start_time=$(date +%s)
    local timeout=300
    local elapsed=0
    
    echo "Measuring time to first Ready/Synced state..."
    
    if [ "${GITOPS_TOOL}" == "argocd" ]; then
        while [ $elapsed -lt $timeout ]; do
            if kubectl get application ${APP_NAME} -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q "Synced"; then
                if kubectl get application ${APP_NAME} -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null | grep -q "Healthy"; then
                    local end_time=$(date +%s)
                    echo $((end_time - start_time))
                    return 0
                fi
            fi
            sleep 2
            elapsed=$(($(date +%s) - start_time))
        done
    else
        while [ $elapsed -lt $timeout ]; do
            if kubectl get kustomization flux-nginx-app -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
                local end_time=$(date +%s)
                echo $((end_time - start_time))
                return 0
            fi
            sleep 2
            elapsed=$(($(date +%s) - start_time))
        done
    fi
    
    echo "timeout"
    return 1
}

measure_self_heal() {
    echo "Measuring self-heal time after manual drift..."
    
    if ! kubectl get deployment ${APP_NAME} -n ${NAMESPACE} >/dev/null 2>&1; then
        echo "0 (deployment not found)"
        return 0
    fi
    
    local original_replicas=$(kubectl get deployment ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
    
    kubectl scale deployment ${APP_NAME} --replicas=0 -n ${NAMESPACE} >/dev/null 2>&1
    sleep 5
    
    local start_time=$(date +%s)
    local timeout=300
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local current_replicas=$(kubectl get deployment ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        local ready_replicas=$(kubectl get deployment ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [ "${current_replicas}" == "${original_replicas}" ] && [ "${ready_replicas}" == "${original_replicas}" ]; then
            local end_time=$(date +%s)
            echo $((end_time - start_time))
            return 0
        fi
        
        sleep 2
        elapsed=$(($(date +%s) - start_time))
    done
    
    echo "timeout"
    return 1
}

measure_rollback() {
    echo "Measuring rollback time..."
    
    if ! kubectl get deployment ${APP_NAME} -n ${NAMESPACE} >/dev/null 2>&1; then
        echo "0 (deployment not found)"
        return 0
    fi
    
    kubectl delete deployment ${APP_NAME} -n ${NAMESPACE} >/dev/null 2>&1 || true
    sleep 5
    
    local start_time=$(date +%s)
    local timeout=300
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get deployment ${APP_NAME} -n ${NAMESPACE} >/dev/null 2>&1; then
            if kubectl wait --for=condition=available deployment/${APP_NAME} -n ${NAMESPACE} --timeout=10s >/dev/null 2>&1; then
                local end_time=$(date +%s)
                echo $((end_time - start_time))
                return 0
            fi
        fi
        
        sleep 2
        elapsed=$(($(date +%s) - start_time))
    done
    
    echo "timeout"
    return 1
}

time_to_ready=$(measure_time_to_ready || echo "timeout")
time_to_heal=$(measure_self_heal || echo "timeout")
time_to_rollback=$(measure_rollback || echo "timeout")

echo ""
echo "Results:"
echo "  Time to Ready: ${time_to_ready}s"
echo "  Time to Self-Heal: ${time_to_heal}s"
echo "  Time to Rollback: ${time_to_rollback}s"
echo ""

echo "${time_to_ready},${time_to_heal},${time_to_rollback}"
