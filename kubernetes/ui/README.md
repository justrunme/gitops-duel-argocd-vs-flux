# UI Kubernetes manifests

## API token Secret (required)

Do **not** commit a bearer token. Create the Secret before applying Deployments:

```bash
kubectl create secret generic ui-backend-api-token \
  --from-literal=token="$(openssl rand -hex 24)" \
  -n default
```

- `ui-backend` reads `UI_API_TOKEN` from key `token`.
- `ui-frontend` nginx reads the same Secret and injects `Authorization: Bearer …` on proxied `/api/*` requests so the browser never holds the token.

Kind / CI e2e generates the Secret the same way (see `.github/workflows/test-kind.yml`).

### Rotate

```bash
kubectl delete secret ui-backend-api-token -n default
kubectl create secret generic ui-backend-api-token \
  --from-literal=token="$(openssl rand -hex 24)" \
  -n default
kubectl rollout restart deployment/ui-backend deployment/ui-frontend -n default
```

## Apply order

```bash
# 1) Secret (command above)
# 2) Workloads (do not rely on a committed Secret manifest)
kubectl apply -f kubernetes/ui/backend-rbac.yaml
kubectl apply -f kubernetes/ui/backend-deployment.yaml
kubectl apply -f kubernetes/ui/backend-service.yaml
kubectl apply -f kubernetes/ui/frontend-deployment.yaml
kubectl apply -f kubernetes/ui/frontend-service.yaml
kubectl apply -f kubernetes/ui/ingress.yaml
```

## Local development without a token

Set `AUTH_DISABLED=true` on the backend process only for local development. The process logs a loud warning and leaves `/api/*` open. Never enable this in shared clusters. `/healthz` stays unauthenticated in all modes.

## Threat model note

The token protects `ui-backend` from direct access (other pods, port-forwards, a misrouted Service). Anyone who can reach `ui-frontend` can still use the API through its proxy, because nginx adds the token for them. Expose the UI only behind your own access control (an ingress with SSO/basic auth, or a VPN) and never publish it to the internet unprotected.
