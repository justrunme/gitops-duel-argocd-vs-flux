# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

Source run: [`38090813003`](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38090813003) (Demo results), 2026-10-10.

## Latest measured results

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Rollback (s) |
|------|-------------------|----------------------|---------------------|
| Argo CD | 4.695 | 3.156 | 4.621 |
| Flux | 6.803 | 13.326 | 69.040 |

Run date: 2026-10-10 22:21:02 UTC

These values are taken verbatim from the CI artifact / job logs. No estimated timings are published.

## How metrics are measured

- **Time to Ready**: delete the Argo CD Application / Flux Kustomization and wipe the target workload, then start the timer at recreate (`date +%s.%N`) and stop when the Deployment is Available and the app reports Synced+Healthy / Ready=True
- **Time to Self-Heal**: recover after scaling replicas to 0
- **Time to Rollback**: recover after deployment deletion

Re-run: Actions → **Demo results** → Run workflow.
