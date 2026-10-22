#!/usr/bin/env bash
# Dump Argo CD install state after a failure.
kubectl get nodes -o wide || true
kubectl describe node || true
helm -n argocd status argocd || true
kubectl -n argocd get pods,jobs,deploy,sts -o wide || true
kubectl -n argocd describe pods || true
kubectl -n argocd get events --sort-by=.lastTimestamp || true
