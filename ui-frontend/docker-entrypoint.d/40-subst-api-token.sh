#!/bin/sh
# Inject UI_API_TOKEN into nginx config. Only this variable is substituted so
# nginx runtime variables ($host, $uri, ...) remain intact.
set -eu
TEMPLATE=/etc/nginx/nginx-api.conf.template
OUTPUT=/etc/nginx/conf.d/default.conf

if [ -z "${UI_API_TOKEN:-}" ]; then
  echo "ERROR: UI_API_TOKEN must be set (mounted from Secret ui-backend-api-token)" >&2
  exit 1
fi

envsubst '${UI_API_TOKEN}' < "${TEMPLATE}" > "${OUTPUT}"
