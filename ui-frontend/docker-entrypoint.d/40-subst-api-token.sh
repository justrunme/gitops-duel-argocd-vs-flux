#!/bin/sh
# Inject UI_API_TOKEN and cluster DNS resolver into nginx config.
# Only listed variables are substituted so nginx runtime vars ($host, ...) stay intact.
set -eu
TEMPLATE=/etc/nginx/nginx-api.conf.template
OUTPUT=/etc/nginx/conf.d/default.conf

if [ -z "${UI_API_TOKEN:-}" ]; then
  echo "ERROR: UI_API_TOKEN must be set (mounted from Secret ui-backend-api-token)" >&2
  exit 1
fi

# Prefer an explicit override; otherwise use the first nameserver from resolv.conf
# (CoreDNS in Kubernetes, Docker embedded DNS locally).
if [ -z "${NGINX_RESOLVER:-}" ]; then
  NGINX_RESOLVER=$(awk '$1 == "nameserver" { print $2; exit }' /etc/resolv.conf || true)
fi
if [ -z "${NGINX_RESOLVER}" ]; then
  echo "ERROR: could not determine NGINX_RESOLVER from /etc/resolv.conf" >&2
  exit 1
fi
export NGINX_RESOLVER
echo "40-subst-api-token: using NGINX_RESOLVER=${NGINX_RESOLVER}"

envsubst '${UI_API_TOKEN} ${NGINX_RESOLVER}' < "${TEMPLATE}" > "${OUTPUT}"
