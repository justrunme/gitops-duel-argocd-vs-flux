#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs
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

echo "Running Argo CD benchmarks..."
argocd_out=$(mktemp)
.github/scripts/benchmark-gitops.sh default nginx-app argocd | tee "$argocd_out"
argocd_results=$(tail -1 "$argocd_out")
IFS=',' read -r argocd_ready argocd_heal argocd_rollback <<<"$argocd_results"
echo "| Argo CD | ${argocd_ready} | ${argocd_heal} | ${argocd_rollback} |" >> docs/results.md

terraform apply -auto-approve
sleep 30

echo "Running Flux benchmarks..."
flux_out=$(mktemp)
.github/scripts/benchmark-gitops.sh default nginx-app flux | tee "$flux_out"
flux_results=$(tail -1 "$flux_out")
IFS=',' read -r flux_ready flux_heal flux_rollback <<<"$flux_results"
echo "| Flux | ${flux_ready} | ${flux_heal} | ${flux_rollback} |" >> docs/results.md
echo "" >> docs/results.md
echo "Run date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> docs/results.md
echo "Source run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-local}" >> docs/results.md
cat docs/results.md
