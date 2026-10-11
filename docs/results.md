# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

Samples per metric: **3** (reported as median with min/max).

Profiles:

| Profile | Argo CD `timeout.reconciliation` | Flux GitRepository/Kustomization `interval` |
|---------|-----------------------------------|-----------------------------------------------|
| `equal-10s` | 10s | 10s |
| `defaults` | 180s (Argo stock) | 1m (CI-bounded stand-in; stock Flux Kustomization default is 10m) |

Commit→ready pushes an image-tag change to a temporary `ci/bench-<run-id>` GitHub branch and times convergence (polling only; no webhooks). The branch is deleted in an `if: always()` cleanup step.

Deletion recovery recreates a deleted Deployment (not a Git revert).

## Profile `equal-10s`

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Deletion Recovery (s) | Time to Commit→Ready (s) |
|------|-------------------|----------------------|-------------------------------|--------------------------|
| Argo CD | 3.759 (min 3.161, max 4.366, n=3) | 3.666 (min 3.623, max 3.671, n=3) | 3.130 (min 3.116, max 3.146, n=3) | 19.068 (min 15.300, max 36.912, n=3) |
| Flux | 6.167 (min 6.136, max 6.187, n=3) | 12.767 (min 11.716, max 13.357, n=3) | 70.208 (min 69.905, max 70.444, n=3) | 8.289 (min 4.006, max 8.843, n=3) |

## Profile `defaults`

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Deletion Recovery (s) | Time to Commit→Ready (s) |
|------|-------------------|----------------------|-------------------------------|--------------------------|
| Argo CD | 3.768 (min 3.729, max 3.843, n=3) | 3.623 (min 3.603, max 3.635, n=3) | 3.170 (min 3.153, max 3.767, n=3) | 312.054 (min 206.794, max 344.024, n=3) |
| Flux | 6.130 (min 6.127, max 6.166, n=3) | 65.157 (min 64.444, max 66.093, n=3) | 119.997 (min 119.985, max 120.506, n=3) | 54.182 (min 53.135, max 57.425, n=3) |

Run date: 2026-10-11 11:00:03 UTC
Source run: https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38131680035

These values are taken verbatim from the CI job. No estimated timings are published.
