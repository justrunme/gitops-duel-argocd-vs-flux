# Security Policy

## Supported versions

Only the latest release receives security fixes.

## UI API authentication

`/api/*` on `ui-backend` requires a Bearer token (`UI_API_TOKEN`) in every environment.
`/healthz` stays open for probes.

- Create the Kubernetes Secret (never commit the value):

  ```bash
  kubectl create secret generic ui-backend-api-token \
    --from-literal=token="$(openssl rand -hex 24)" \
    -n default
  ```

- The browser does not hold the token. `ui-frontend` nginx proxies `/api/*` to the
  backend and injects `Authorization` from the same Secret (see
  `ui-frontend/nginx.conf.template` and `kubernetes/ui/README.md`).
- Local-only escape hatch: `AUTH_DISABLED=true` skips auth and logs a loud warning.
  Do not use this in shared or production clusters.

## Reporting a vulnerability

Please do not open a public issue for security problems. Report them privately via
[GitHub Security Advisories](../../security/advisories/new) for this repository.

You can expect an initial response within 7 days. Once the issue is confirmed, a fix
is prepared in a private branch and released together with an advisory.
