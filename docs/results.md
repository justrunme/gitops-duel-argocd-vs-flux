# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

Source run: [`38084720453`](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38084720453) (Demo results) and [`38084720313`](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38084720313) (GitOps Duel CI), 2026-10-10.

## Latest measured results

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Rollback (s) |
|------|-------------------|----------------------|---------------------|
| Argo CD | timeout (app not Synced/Healthy within 300s) | 0 (deployment not found) | 0 (deployment not found) |
| Flux | 0 (deployment not found) | 0 (deployment not found) | 0 (deployment not found) |

Run date: 2026-10-10 20:57:35 UTC

These values are taken verbatim from the CI artifact / job logs. No estimated timings are published.

## How metrics are measured

- **Time to Ready**: deployment creation → first Synced/Ready (`benchmark-gitops.sh`)
- **Time to Self-Heal**: recover after scaling replicas to 0
- **Time to Rollback**: recover after deployment deletion

Re-run: Actions → **Demo results** → Run workflow.
