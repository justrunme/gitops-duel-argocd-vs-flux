# GitOps Performance Benchmarks

Automated performance comparison between Argo CD and Flux.

## Metrics

Performance metrics are measured in the CI pipeline for:
- **Time to Ready**: Time from deployment creation to first Synced/Ready state
- **Time to Self-Heal**: Time to recover after manual drift (scaling replicas to 0)
- **Time to Rollback**: Time to recover after deployment deletion

Results are automatically updated on each CI run.

## Latest Results

See the latest CI run for current performance metrics.
