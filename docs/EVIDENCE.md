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
| Time to Ready / Self-Heal / Deletion Recovery / Commit→Ready benchmarks | Tested in CI | Same CI job + Demo results methodology (N=3 median/min/max, `equal-10s` + `defaults`, commit→ready); timers around recreate / scale-to-0 / deployment delete as implemented in the workflow | Kind + small nginx — not fleet-scale GitOps; Flux deletion recovery ~70 s in this lab is still a lab sample | Committed [docs/results.md](results.md) from Demo results run [38131680035](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38131680035) (measured_at `2026-10-11T11:00:03Z`): equal-10s Argo CD ready **3.759 s**, self-heal **3.666 s**, deletion recovery **3.130 s**, commit→ready **19.068 s**; Flux ready **6.167 s**, self-heal **12.767 s**, deletion recovery **70.208 s**, commit→ready **8.289 s** | Self-heal/deletion-recovery paths fail the job if apps do not recover |
| Error simulation (delete / scale replicas) verifies self-healing | Tested in CI | CI steps “Simulate ArgoCD/Flux Deployment Issues” | Synthetic faults in CI, not production GameDays | Same CI workflow on run 38115920047 | Recovery must restore desired state or job fails |
| Custom UI compares Git desired vs live manifests | Reference implementation | `ui-backend` / `ui-frontend` built and loaded into kind in CI | UI is a demo comparator, not an enterprise GitOps console soak | Images loaded in CI (`kind load docker-image …`); no separate UI latency SLO in results | — |
| Multi-cluster / multi-region GitOps performance | Not yet | — | Out of kind duel scope | — | — |

## Not proven / out of scope

- Treating kind benchmark seconds as contractual production sync SLOs
- Multi-primary / multi-region Argo CD or Flux topologies
- Equating sample nginx apps with large multi-thousand-application fleets
- Note: branch `fix/ui-backend-review` lands hardened UI (namespaced RBAC, bearer auth, git-manifests limits) + methodology tables; [docs/results.md](results.md) cites Demo results run 38131680035

## How to reproduce

```bash
terraform init
terraform apply -auto-approve
# CI path:
# Actions → GitOps Duel CI (test-kind.yml) on main
# Optional: Actions → Demo results → Run workflow
```

Artifact name: `gitops-benchmark-results`.
