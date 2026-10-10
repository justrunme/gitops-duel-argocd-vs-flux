# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

Source run: [`38089699018`](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38089699018) (Demo results), 2026-10-10.

## Latest measured results

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Rollback (s) |
|------|-------------------|----------------------|---------------------|
| Argo CD | 0 | 2 | 5 |
| Flux | 0 | 9 | 14 |

Run date: 2026-10-10 22:02:01 UTC

These values are taken verbatim from the CI artifact / job logs. No estimated timings are published.

Time to Ready can be `0` when the Application / Kustomization is already Synced/Ready before the benchmark timer starts (controllers were installed in earlier workflow steps). Self-Heal and Rollback always force drift after that point.

## How metrics are measured

- **Time to Ready**: wait until Argo CD Application is Synced+Healthy (or Flux Kustomization Ready) and `nginx-app` has ready replicas (`benchmark-gitops.sh`)
- **Time to Self-Heal**: recover after scaling replicas to 0
- **Time to Rollback**: recover after deployment deletion

Re-run: Actions → **Demo results** → Run workflow.
