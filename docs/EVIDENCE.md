# Evidence

Maps GitOps duel claims to CI proof. Status vocabulary: **Tested in CI** /
**Reference implementation** / **Simulated** / **Not yet**.

Benchmark seconds below are taken from the **GitOps Duel CI** artifact
`gitops-benchmark-results` on a successful `main` run (and/or the committed
`docs/results.*` when that file matches a cited run). **Single-node kind numbers
are lab timings for sample Helm nginx apps — not multi-cluster production sync SLOs.**

## Claim table

| Claim | Status | Scenario + environment | Real limits | Proof link | Negative tests |
| --- | --- | --- | --- | --- | --- |
| Side-by-side Argo CD + Flux deploy on kind | Tested in CI | Workflow **GitOps Duel CI** (`.github/workflows/test-kind.yml`); `helm/kind-action@v1.15.1`; Terraform modules for Argo CD + Flux; sample Helm nginx apps | Single-node kind; demo charts only | Latest green main CI: [38115920047](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38115920047) · SHA `689343c101a2044d1d3d1cc1c1766b52be8c4bfc` · job `gitops-duel-ci` · artifact `gitops-benchmark-results` | Workflow fails if deploy/sync asserts fail |
| Time to Ready / Self-Heal / Deletion Recovery / Commit→Ready benchmarks | Tested in CI | Same CI job; timers around recreate / scale-to-0 / deployment delete as implemented in the workflow | Kind + small nginx — not fleet-scale GitOps; Flux rollback ~70 s in this lab is still a lab sample | Artifact from [38115920047](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38115920047) (measured_at `2026-10-11T05:52:19Z`): Argo CD ready **6.761 s**, self-heal **3.518 s**, rollback **3.172 s**; Flux ready **6.076 s**, self-heal **13.124 s**, rollback **70.176 s**. Committed [docs/results.md](results.md) still cites older Demo results run [38090813003](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38090813003) (different numbers) — prefer the linked CI artifact for the newest main proof | Self-heal/rollback paths fail the job if apps do not recover |
| Error simulation (delete / scale replicas) verifies self-healing | Tested in CI | CI steps “Simulate ArgoCD/Flux Deployment Issues” | Synthetic faults in CI, not production GameDays | Same CI workflow on run 38115920047 | Recovery must restore desired state or job fails |
| Custom UI compares Git desired vs live manifests | Reference implementation | `ui-backend` / `ui-frontend` built and loaded into kind in CI | UI is a demo comparator, not an enterprise GitOps console soak | Images loaded in CI (`kind load docker-image …`); no separate UI latency SLO in results | — |
| Multi-cluster / multi-region GitOps performance | Not yet | — | Out of kind duel scope | — | — |

## Not proven / out of scope

- Treating kind benchmark seconds as contractual production sync SLOs
- Multi-primary / multi-region Argo CD or Flux topologies
- Equating sample nginx apps with large multi-thousand-application fleets
- Note: branch `fix/ui-backend-review` lands hardened UI (namespaced RBAC, bearer auth, git-manifests limits) + methodology tables; proof links refreshed from Demo results run 38129173686 and the PR GitOps Duel CI run after merge

## How to reproduce

```bash
terraform init
terraform apply -auto-approve
# CI path:
# Actions → GitOps Duel CI (test-kind.yml) on main
# Optional: Actions → Demo results → Run workflow
```

Artifact name: `gitops-benchmark-results`.
