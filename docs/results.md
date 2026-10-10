# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

## Metrics

| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Rollback (s) |
|------|-------------------|----------------------|---------------------|

Results are written by CI (`demo-results` / `test-kind` workflows) and committed from the uploaded artifact. See the source Actions run linked from the README Results table once populated.

## How metrics are measured

- **Time to Ready**: deployment creation → first Synced/Ready
- **Time to Self-Heal**: recover after scaling replicas to 0
- **Time to Rollback**: recover after deployment deletion
