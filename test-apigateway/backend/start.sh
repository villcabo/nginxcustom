#!/bin/sh
set -e

BACKEND_ID="${BACKEND_ID:-unknown}"
STARTUP_DELAY="${STARTUP_DELAY:-20}"

echo "[$(date -u +%H:%M:%S)] backend=${BACKEND_ID} cold-starting (${STARTUP_DELAY}s)..."
sleep "$STARTUP_DELAY"

# Substitute BACKEND_ID into the nginx config template.
sed "s|__BACKEND_ID__|${BACKEND_ID}|g" \
    /etc/nginx/templates/default.conf.tmpl \
    > /etc/nginx/conf.d/default.conf

echo "[$(date -u +%H:%M:%S)] backend=${BACKEND_ID} ready, starting nginx"
exec nginx -g "daemon off;"
