# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

Source run: [`38090813003`](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38090813003) (Demo results), 2026-10-10.

> Numbers below are from the last published CI artifact. They will be replaced only with values from a green CI run on this branch (N=3 median/min/max, `equal-10s` + `defaults` profiles, including commit→ready). No estimated timings are published.

## Latest measured results

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Rollback (s) |
|------|-------------------|----------------------|---------------------|
| Argo CD | 4.695 | 3.156 | 4.621 |
| Flux | 6.803 | 13.326 | 69.040 |

Run date: 2026-10-10 22:21:02 UTC

These values are taken verbatim from the CI artifact / job logs. No estimated timings are published.

## How metrics are measured

- **Profiles**
  - `equal-10s`: Argo CD `timeout.reconciliation=10s`, Flux GitRepository/Kustomization `interval=10s`
  - `defaults`: Argo CD `timeout.reconciliation=180s` (stock), Flux `interval=1m` (CI-bounded stand-in; stock Flux Kustomization default is 10m)
- **Samples**: N=3 per metric; published as median with min/max
- **Time to Ready**: delete the Argo CD Application / Flux Kustomization and wipe the target workload, then start the timer at recreate and stop when the Deployment is Available and the app reports Synced+Healthy / Ready=True
- **Time to Self-Heal**: recover after scaling replicas to 0
- **Time to Deletion Recovery** (table header may still say Rollback in older artifacts): recover after deployment deletion (not a Git revert)
- **Time to Commit→Ready**: push an image-tag change to a temporary `ci/bench-<run-id>` GitHub branch and time until the live Deployment image converges (polling only; no webhooks). The branch is deleted in an `if: always()` cleanup step.

Re-run: Actions → **Demo results** or **GitOps Duel CI**.
