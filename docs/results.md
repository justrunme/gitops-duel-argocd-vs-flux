# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

> Pending: this file will be replaced with numbers from a fresh green CI run of the current methodology on this branch (N=3 median/min/max, `equal-10s` + `defaults`, including commit→ready and **Time to Deletion Recovery** — not “Rollback”). No estimated timings are published.

## How metrics are measured

- **Profiles**
  - `equal-10s`: Argo CD `timeout.reconciliation=10s`, Flux GitRepository/Kustomization `interval=10s`
  - `defaults`: Argo CD `timeout.reconciliation=180s` (stock), Flux `interval=1m` (CI-bounded stand-in; stock Flux Kustomization default is 10m)
- **Samples**: N=3 per metric; published as median with min/max
- **Time to Ready**: delete the Argo CD Application / Flux Kustomization and wipe the target workload, then start the timer at recreate and stop when the Deployment is Available and the app reports Synced+Healthy / Ready=True
- **Time to Self-Heal**: recover after scaling replicas to 0
- **Time to Deletion Recovery**: recover after deployment deletion (not a Git revert)
- **Time to Commit→Ready**: push an image-tag change to a temporary `ci/bench-<run-id>` GitHub branch and time until the live Deployment image converges (polling only; no webhooks). The branch is deleted in an `if: always()` cleanup step.

Re-run: Actions → **GitOps Duel CI**.
