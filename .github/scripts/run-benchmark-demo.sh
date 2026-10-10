#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs

ARGO_NS=${ARGO_TARGET_NAMESPACE:-argocd-demo}
FLUX_NS=${FLUX_TARGET_NAMESPACE:-flux-demo}

{
  echo "# GitOps Performance Benchmarks"
  echo ""
  echo "Automated performance comparison between Argo CD and Flux."
  echo ""
  echo "## Metrics"
  echo ""
  echo "| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Rollback (s) |"
  echo "|------|-------------------|----------------------|---------------------|"
} > docs/results.md

echo "Running Argo CD benchmarks..." >&2
argocd_results=$(.github/scripts/benchmark-gitops.sh "${ARGO_NS}" nginx-app argocd)
IFS=',' read -r argocd_ready argocd_heal argocd_rollback <<<"${argocd_results}"

# Reject non-numeric / masked failures
for v in "${argocd_ready}" "${argocd_heal}" "${argocd_rollback}"; do
  [[ "${v}" =~ ^[0-9]+$ ]] || { echo "Argo CD benchmark failed: ${argocd_results}" >&2; exit 1; }
done
echo "| Argo CD | ${argocd_ready} | ${argocd_heal} | ${argocd_rollback} |" >> docs/results.md

echo "Running Flux benchmarks..." >&2
flux_results=$(.github/scripts/benchmark-gitops.sh "${FLUX_NS}" nginx-app flux)
IFS=',' read -r flux_ready flux_heal flux_rollback <<<"${flux_results}"

for v in "${flux_ready}" "${flux_heal}" "${flux_rollback}"; do
  [[ "${v}" =~ ^[0-9]+$ ]] || { echo "Flux benchmark failed: ${flux_results}" >&2; exit 1; }
done
echo "| Flux | ${flux_ready} | ${flux_heal} | ${flux_rollback} |" >> docs/results.md
echo "" >> docs/results.md
echo "Run date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> docs/results.md
echo "Source run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-local}" >> docs/results.md
cat docs/results.md
