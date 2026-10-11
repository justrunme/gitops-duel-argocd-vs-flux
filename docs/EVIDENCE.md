# Evidence

Maps GitOps duel claims to CI proof. Status vocabulary: **Tested in CI** /
**Reference implementation** / **Simulated** / **Not yet**.

Benchmark seconds below are taken from the **GitOps Duel CI** artifact
`gitops-benchmark-results` on a successful run of the hardened benchmark path
(and mirrored in [docs/results.md](results.md) / [docs/results.json](results.json)).
**Single-node kind numbers are lab timings for sample Helm nginx apps — not
multi-cluster production sync SLOs.**

## Claim table

| Claim | Status | Scenario + environment | Real limits | Proof link | Negative tests |
| --- | --- | --- | --- | --- | --- |
| Side-by-side Argo CD + Flux deploy on kind | Tested in CI | Workflow **GitOps Duel CI** (`.github/workflows/test-kind.yml`); `helm/kind-action@v1.15.1`; Terraform modules for Argo CD + Flux; sample Helm nginx apps | Single-node kind; demo charts only | Green CI on fix tip: [38124520961](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/runs/38124520961) · SHA `7d50e8c0829709347345f14ba10c8a0c43636fa9` · job `gitops-duel-ci` · artifact `gitops-benchmark-results`. Squash-merged to main as `44700575` (#27) | Workflow fails if deploy/sync asserts fail |
| Time to Ready / Self-Heal / Deletion Recovery / Commit→Ready (N=3, profiles) | Tested in CI | Profiles `equal-10s` and `defaults`; temporary `ci/bench-<run-id>` branch for commit→ready; kind + nginx | Kind lab only; Flux deletion-recovery ~70 s (`equal-10s`) / ~120 s (`defaults`) is still a lab sample, not a fleet SLO | Same artifact/run: primary profile `equal-10s` medians — Argo CD ready **4.110 s**, self-heal **3.326 s**, deletion recovery **3.670 s**, commit→ready **16.431 s**; Flux ready **6.443 s**, self-heal **11.778 s**, deletion recovery **69.959 s**, commit→ready **8.095 s**. Full min/max/N and `defaults` profile in [docs/results.md](results.md) | Self-heal / deletion-recovery / commit→ready asserts fail the job on invalid samples |
| Error simulation (delete / scale replicas) verifies self-healing | Tested in CI | CI steps “Simulate ArgoCD/Flux Deployment Issues” after controllers are restored to the CI-tracked branch | Synthetic faults in CI, not production GameDays | Same CI run 38124520961 (passed Simulate steps after benchmark restore) | Recovery must restore desired state or job fails |
| ui-backend hardened against command injection | Tested in CI | Job **ui-backend-unit** (`npm test` + grep guard forbidding `child_process`/`exec` in request path) | Covers API input validation unit tests; not a full pentest | Same workflow · `ui-backend-unit` success on run 38124520961 | Malicious input rejection tests fail CI |
| Custom UI compares Git desired vs live manifests | Reference implementation | `ui-backend` / `ui-frontend` built and loaded into kind in CI | UI is a demo comparator, not an enterprise GitOps console soak | Images loaded in CI (`kind load docker-image …`); no separate UI latency SLO in results | — |
| Multi-cluster / multi-region GitOps performance | Not yet | — | Out of kind duel scope | — | — |

## Not proven / out of scope

- Treating kind benchmark seconds as contractual production sync SLOs
- Multi-primary / multi-region Argo CD or Flux topologies
- Equating sample nginx apps with large multi-thousand-application fleets

## How to reproduce

```bash
terraform init
terraform apply -auto-approve
# CI path:
# Actions → GitOps Duel CI (test-kind.yml) on main
# Optional: Actions → Demo results → Run workflow
```

Artifact name: `gitops-benchmark-results`.
