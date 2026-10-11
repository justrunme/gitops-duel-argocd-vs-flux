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
| Argo CD | 4.110 (min 3.519, max 4.705, n=3) | 3.326 (min 3.302, max 3.944, n=3) | 3.670 (min 3.542, max 4.187, n=3) | 16.431 (min 14.830, max 56.718, n=3) |
| Flux | 6.443 (min 6.426, max 6.474, n=3) | 11.778 (min 11.770, max 12.954, n=3) | 69.959 (min 69.933, max 70.501, n=3) | 8.095 (min 3.607, max 9.212, n=3) |

## Profile `defaults`

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Deletion Recovery (s) | Time to Commit→Ready (s) |
|------|-------------------|----------------------|-------------------------------|--------------------------|
| Argo CD | 4.086 (min 4.079, max 4.675, n=3) | 3.882 (min 3.316, max 3.893, n=3) | 3.500 (min 3.454, max 4.109, n=3) | 313.134 (min 204.953, max 324.601, n=3) |
| Flux | 6.418 (min 5.948, max 6.443, n=3) | 62.963 (min 59.360, max 64.764, n=3) | 120.245 (min 120.125, max 120.786, n=3) | 53.769 (min 52.132, max 58.263, n=3) |

Run date: 2026-10-11 08:59:54 UTC
Source run: https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38124520961

These values are taken verbatim from the CI job. No estimated timings are published.
