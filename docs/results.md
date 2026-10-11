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
| Argo CD | 4.191 (min 3.627, max 4.205, n=3) | 3.384 (min 3.321, max 3.926, n=3) | 3.540 (min 2.867, max 4.195, n=3) | 16.083 (min 14.236, max 16.579, n=3) |
| Flux | 6.456 (min 6.432, max 6.489, n=3) | 13.050 (min 12.420, max 13.080, n=3) | 70.335 (min 69.950, max 70.444, n=3) | 8.734 (min 3.589, max 9.242, n=3) |

## Profile `defaults`

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Deletion Recovery (s) | Time to Commit→Ready (s) |
|------|-------------------|----------------------|-------------------------------|--------------------------|
| Argo CD | 4.167 (min 3.560, max 4.170, n=3) | 3.316 (min 3.312, max 3.917, n=3) | 3.490 (min 3.483, max 4.143, n=3) | 183.890 (min 176.438, max 358.543, n=3) |
| Flux | 6.451 (min 6.440, max 6.480, n=3) | 61.267 (min 60.727, max 62.460, n=3) | 119.841 (min 119.729, max 120.076, n=3) | 52.755 (min 51.435, max 58.885, n=3) |

Run date: 2026-10-11 10:14:48 UTC
Source run: https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38129173686

These values are taken verbatim from the CI job. No estimated timings are published.
