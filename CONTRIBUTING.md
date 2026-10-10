# Contributing

## Development setup

```bash
# Terraform dual-stack (Kind)
terraform init
# UI
cd ui-frontend && npm ci
cd ../ui-backend && npm ci
```

## Branch naming

- `feat/<short-name>`
- `fix/<short-name>`
- `chore/<short-name>`
- `docs/<short-name>`
- `ci/<short-name>`

## Commits

Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`, `ci:`.

## Tests

```bash
# Frontend unit tests
cd ui-frontend && npm test -- --watchAll=false
# Kind integration (matches CI workflow test-kind.yml)
# terraform apply against a Kind cluster, then drift/recovery scenarios
```

## Pull requests

Open against `main`. CI (`test-kind`) must be green when infra/UI paths change. Squash merge preferred.

Checklist:

- [ ] UI builds (`npm run build` in `ui-frontend`)
- [ ] Terraform configs remain applyable on Kind
- [ ] Branch naming follows convention
- [ ] Conventional commits
- [ ] Docs updated for scenario changes
